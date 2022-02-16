
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `dialdroid`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `calculatedataleak` ()  BEGIN

declare default_category INT DEFAULT 3;
DECLARE finished INTEGER DEFAULT 0;

DECLARE category_cursor CURSOR for SELECT id from CategoryStrings  where st='android.intent.category.DEFAULT';
DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = 1;

OPEN category_cursor;
		
FETCH category_cursor INTO default_category;


-- URI parsing
TRUNCATE ParsedURI;
 insert into ParsedURI SELECT id,scheme, path, IF( LOCATE(':',host_port)>0, SUBSTRING(host_port,1,LOCATE(':',host_port)-1 ), host_port)  as host, 
IF( LOCATE(':',host_port)>0, SUBSTRING(host_port,LOCATE(':',host_port)+1), null)  as port, orig_uri 

 from (
select id,CASE WHEN uri='(.*)' THEN uri ELSE  substring_index(uri,'://',1) END  as scheme,
 CASE WHEN uri='(.*)' THEN uri ELSE substring_index( SUBSTRING(uri, LOCATE('://', uri) + 3),'/',1) END AS host_port, 
IF (LOCATE('/',SUBSTRING(uri, LOCATE('://', uri) + 3))>0, SUBSTRING(SUBSTRING(uri, LOCATE('://', uri) + 3) ,LOCATE('/',SUBSTRING(uri, LOCATE('://', uri) + 3))+1),null )as path,
uri as orig_uri
from UriData ) uriparse;

UPDATE ParsedURI set scheme='tel' where orig_uri like 'tel:%';
UPDATE ParsedURI set scheme='file' where orig_uri like 'file:%';
UPDATE ParsedURI set scheme='vnd.youtube' where orig_uri like 'vnd.youtube:%';
UPDATE ParsedURI set scheme='sms' where orig_uri like 'smsto:%';
UPDATE ParsedURI set scheme='mailto' where orig_uri like 'mailto:%';
UPDATE ParsedURI set scheme='geo' where orig_uri like 'geo:%';
UPDATE ParsedURI set scheme='package' where orig_uri like 'package:%';
UPDATE ParsedURI set scheme='google.navigation' where orig_uri like 'google.navigation:%';
UPDATE ParsedURI set scheme='skype' where orig_uri like 'skype:%';
UPDATE ParsedURI set scheme='ticker' where orig_uri like 'ticker:%';
UPDATE ParsedURI set scheme='sip' where orig_uri like 'sip:%';
UPDATE ParsedURI set scheme='market' where orig_uri like 'market:%';
UPDATE ParsedURI set scheme='facebook' where orig_uri like 'facebook:%';
UPDATE ParsedURI set scheme='exe' where orig_uri like 'exe:%';

 -- find out data leaking apps
 TRUNCATE SensitiveChannels;
 
 
  -- Broadcast receiver leaks
  insert into SensitiveChannels
 select DISTINCT I.app_id as fromapp,  G.app_id as toapp, A.id as intent_id,
 E.id as exitpoint, 	G.id as entryclass, iflt.id as filter_id, 'R' as icc_type	 
	  from 
	Intents A  
	inner join ExitPoints E on E.id=A.exit_id and A.implicit=1 and E.exit_kind ='r'
   inner join ICCExitLeaks idl on idl.exit_point_id = E.id and idl.disabled=0
	inner join IntentActions act on A.id=act.intent_id
	inner join IFilterActions ifac on ifac.`action`=act.`action`
	inner join IntentFilters iflt on ifac.filter_id=iflt.id
	inner join Components F on F.id=iflt.component_id and F.kind='r'
	inner join Classes G on G.id=F.class_id 
		inner join Classes I on E.class_id=I.id;

-- Provider leaks
  insert into SensitiveChannels		
SELECT DISTINCT  cs.app_id as fromapp,  Classes.app_id as toapp, Uris.id as intent_id,
 Uris.exit_id as exitpoint, 	Classes.id as entryclass, 
  ProviderAuthorities.provider_id as filter_id, 'P' as icc_type	  
 FROM  `Uris` inner join `ParsedURI` 
 on Uris.data=ParsedURI.id
INNER JOIN ProviderAuthorities on ProviderAuthorities.authority=ParsedURI.host
and ParsedURI.scheme='content'
INNER JOIN Providers on Providers.id=ProviderAuthorities.provider_id
INNER JOIN Components on Components.id=Providers.component_id
INNER JOIN ICCExitLeaks on ICCExitLeaks.exit_point_id=Uris.exit_id
INNER JOIN Classes on Classes.id=Components.class_id
INNER JOIN ExitPoints on ExitPoints.id=ICCExitLeaks.exit_point_id
and ExitPoints.exit_kind='p'
INNER JOIN Classes cs on cs.id=ExitPoints.class_id;


-- Explicit intra-app ICC Leaks 
  insert into SensitiveChannels
SELECT DISTINCT F.app_id as fromapp,  B.app_id as toapp, C.id as intent_id,
 E.id as exitpoint, 	B.id as entryclass, null as filter_id, 'X' as icc_type	
 FROM
IntentClasses A inner join Classes B
on A.class=B.class
inner join Intents C on A.intent_id=C.id and C.implicit=0 
Inner join IntentPackages P on P.intent_id=C.id
inner join ExitPoints E on E.id=C.exit_id
inner join Classes F on E.class_id=F.id
inner join ICCExitLeaks H on H.exit_point_id=C.exit_id and H.disabled=0
Inner join Applications G on G.id=B.app_id
WHERE B.app_id =F.app_id and (( P.package=G.app) or (P.package='(.*)'));

-- Explicit inter-app ICC leaks

insert into SensitiveChannels
SELECT DISTINCT F.app_id as fromapp,  B.app_id as toapp, C.id as intent_id,
 E.id as exitpoint, 	F.id as entryclass, null as filter_id, 'X' as icc_type	
 FROM
IntentClasses A inner join Classes B
on A.class=B.class
inner join Intents C on A.intent_id=C.id and C.implicit=0 
 INNER JOIN Components T on T.class_id=B.id and T.exported=1
Inner join IntentPackages P on P.intent_id=C.id
inner join ExitPoints E on E.id=C.exit_id
inner join Classes F on E.class_id=F.id
inner join ICCExitLeaks H on H.exit_point_id=C.exit_id
Inner join Applications G on G.id=B.app_id
WHERE B.app_id !=F.app_id 
 and (( P.package=G.app) or (P.package='(.*)'));
 
   
 -- Explicit inter-app ICC leaks with returned results
 insert into SensitiveChannels 
  SELECT DISTINCT F.app_id as fromapp,  B.app_id as toapp, C.id as intent_id,
 rp.id as exitpoint, F.id as entryclass, NULL as filter_id, 'X' as icc_type	
 FROM
IntentClasses A inner join Classes B on A.class=B.class
inner join Intents C on A.intent_id=C.id and C.implicit=0 
Inner join IntentPackages P on P.intent_id=C.id
inner join ExitPoints E on E.id=C.exit_id and E.statement like '%startActivityForResult%'
inner join Classes F on E.class_id=F.id
inner join ExitPoints rp on rp.class_id=B.id
inner join ICCExitLeaks H on H.exit_point_id=rp.id and H.disabled=0 and H.leak_sink like '%setResult%'
Inner join Applications G on G.id=B.app_id
WHERE B.app_id =F.app_id and (( P.package=G.app) or (P.package='(.*)'));


   
 -- Implicit ICC channels
 insert into SensitiveChannels
 
select  
DISTINCT fromapp,  entryCls.app_id as toapp, intent_id,
  exitpoint, 	entryCls.id as entryclass, filter_id, 'I' as icc_type	  FROM
( select intent.id as intent_id,ep.id as exitpoint,iac.`action`,icat.category,
idt.id as data_id,imt.id as mime_id,cls.app_id as fromapp
	  from 
	  ICCExitLeaks idl inner join ExitPoints ep on idl.exit_point_id =ep.id and 
	  ep.exit_kind in ('a','s') and idl.disabled=0
	  INNER join Classes cls on ep.class_id=cls.id
	  inner join Intents intent  on intent.exit_id=ep.id and intent.implicit=1
	left join IntentActions iac on intent.id =iac.intent_id 
	left join IntentCategories icat on intent.id=icat.intent_id
    left join IntentData idt on intent.id=idt.intent_id
    left join IntentMimeTypes imt on intent.id=imt.intent_id ) vulIntents
 inner join 
   (
	select iflt.id as filter_id,ifa.`action`,ifc.category,ifdt.id as filter_data,iflt.component_id
	  from 
	IntentFilters iflt  
	left join IFilterActions ifa on iflt.id =ifa.filter_id
	left join IFilterCategories ifc on iflt.id=ifc.filter_id
    left join IFilterData ifdt on iflt.id=ifdt.filter_id
	) allFilters
 	on ( (vulIntents.`action` is null and allFilters.`action` is not null) or (vulIntents.`action` = allFilters.`action`)) and 
 	((vulIntents.category=allFilters.category) or (vulIntents.category is NULL and allFilters.category=default_category))
 	and (categorytest(vulIntents.intent_id,allFilters.filter_id)=1)
 	inner join Components comp on comp.id= component_id
 	inner join Classes entryCls on entryCls.id=comp.class_id	
 	WHERE  	 ((vulIntents.data_id is NULL and vulIntents.mime_id is null and allFilters.filter_data is null) 
 	or (datatest(vulIntents.intent_id,allFilters.filter_id)=1))
 		order by intent_id ;


END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `categorytest` (`intent` INT, `filter` INT) RETURNS TINYINT(4) NO SQL
BEGIN

DECLARE result TINYINT DEFAULT 1;
DECLARE finished,finished1 INTEGER DEFAULT 0;

declare intent_category,intent_match INT DEFAULT 0;

DECLARE intent_cursor CURSOR for SELECT category from IntentCategories where intent_id=intent;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = 1;



OPEN intent_cursor;
 
match_categories: LOOP
	FETCH intent_cursor INTO intent_category;
	
  	IF finished = 1 THEN 
 		LEAVE match_categories;
 	END IF;
      
 	
 	BLOCK2: BEGIN
 	
 		DECLARE filter_cursor CURSOR for SELECT category from IFilterCategories  where filter_id=filter and category=intent_category;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished1 = 1;
		OPEN filter_cursor;
		
		match_filters: LOOP
		
		FETCH filter_cursor INTO intent_match;
			
		IF finished1 = 1 THEN
			set result=0; 
 			LEAVE match_filters;
 		END IF;		 		
		
		CLOSE filter_cursor;
		LEAVE match_filters;
		
		END LOOP match_filters;
 	
 	END BLOCK2;
  
END LOOP match_categories;
 
CLOSE intent_cursor;

RETURN  result;


END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `datatest` (`intent` INT, `filter` INT) RETURNS TINYINT(4) NO SQL
BEGIN

DECLARE filter_scheme,filter_host,filter_port,filter_path,filter_type,filter_subtype VARCHAR(200);
DECLARE intent_scheme,intent_host,intent_port,intent_path,intent_type,intent_subtype VARCHAR(200);
DECLARE orig_uri VARCHAR(512);
DECLARE finished INTEGER DEFAULT 0;
DECLARE result INTEGER DEFAULT 0;

DECLARE filter_cursor CURSOR for   select DISTINCT F.scheme as filter_scheme,F.host as filter_host, F.port as filter_port, F.path as filter_path,
F.`type` as filter_type, F.subtype as filter_subtype,
C.scheme as intent_scheme, C.host as intent_host, C.path as intent_path, 
C.port as intent_port, M.`type` as intent_type, 
M.subtype as intent_subtype, C.orig_uri
 from
 (SELECT id from Intents WHERE id=intent) I left join IntentData intent_data on I.id=intent_data.intent_id 
 left join IntentMimeTypes M on M.intent_id= I.id
left join 
  ParsedURI C on intent_data.`data`=C.id 
 inner join IFilterData F on F.filter_id =filter 
   and  (M.`type`<=> F.`type` or F.type like '%*%') and( M.subtype <=> F.subtype or F.subtype like '%*%') and (C.orig_uri is null or C.orig_uri!='(.*)') and (C.orig_uri is null or C.orig_uri!='(.*)')
 where 
( 
(intent_data.id is null and F.scheme is null and F.host is null) OR
(F.scheme is not null and  F.host is null and F.path is null and C.scheme=F.scheme) OR
(F.path is null and F.scheme = C.scheme and  F.host = C.host  and F.port <=> C.port) OR
(C.path like REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(F.path,'*','%'),'/','%'),'(',''),')',''),'.','') 
and F.scheme = C.scheme and  F.host = C.host  and F.port <=> C.port) OR
(C.scheme in ('file','content') and F.scheme is null and F.host is null and F.`type` is not null) ) ;

 
DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = 1;


OPEN filter_cursor;
 
match_data: LOOP
	FETCH filter_cursor INTO filter_scheme,filter_host,filter_port,filter_path,filter_type,filter_subtype,intent_scheme,intent_host,intent_port,intent_path,intent_type,intent_subtype,orig_uri;
	
  	IF finished = 1 THEN 
 		LEAVE match_data;
 	END IF;
	
	SET result =1; 		
 	 	
END LOOP match_data;
 
CLOSE filter_cursor;

return result;

END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `ActionStrings`
--

CREATE TABLE `ActionStrings` (
  `id` int(11) NOT NULL,
  `st` varchar(191) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Aliases`
--

CREATE TABLE `Aliases` (
  `id` int(11) NOT NULL,
  `component_id` int(11) NOT NULL,
  `target_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `AppAnalysisTime`
--

CREATE TABLE `AppAnalysisTime` (
  `id` int(11) NOT NULL,
  `AppID` int(11) DEFAULT NULL,
  `ModelParse` int(11) DEFAULT NULL,
  `ClassLoad` int(11) DEFAULT NULL,
  `MainGeneration` int(11) DEFAULT NULL,
  `EntryPointMapping` int(11) DEFAULT NULL,
  `IC3TotalTime` int(11) DEFAULT NULL,
  `ExitPointPath` int(11) DEFAULT NULL,
  `EntryPointPath` int(11) DEFAULT NULL,
  `TotalTime` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `AppCategories`
--

CREATE TABLE `AppCategories` (
  `id` int(11) NOT NULL,
  `AppID` int(11) NOT NULL,
  `CategoryID` int(11) NOT NULL,
  `path` varchar(512) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `Applications`
--

CREATE TABLE `Applications` (
  `id` int(11) NOT NULL,
  `app` varchar(512) COLLATE utf8mb4_bin NOT NULL,
  `version` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

ALTER TABLE `Applications` ADD `shasum` VARCHAR(100) NULL DEFAULT NULL AFTER `app`;

-- --------------------------------------------------------

--
-- Table structure for table `AppTimeout`
--

CREATE TABLE `AppTimeout` (
  `id` int(11) NOT NULL,
  `AppID` int(11) NOT NULL,
  `Timeout` tinyint(4) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `Categories`
--

CREATE TABLE `Categories` (
  `id` int(11) NOT NULL,
  `st` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `CategoryStrings`
--

CREATE TABLE `CategoryStrings` (
  `id` int(11) NOT NULL,
  `st` varchar(191) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Classes`
--

CREATE TABLE `Classes` (
  `id` int(11) NOT NULL,
  `app_id` int(11) NOT NULL,
  `class` varchar(191) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `ComponentExtras`
--

CREATE TABLE `ComponentExtras` (
  `id` int(11) NOT NULL,
  `component_id` int(11) NOT NULL,
  `extra` varchar(512) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Components`
--

CREATE TABLE `Components` (
  `id` int(11) NOT NULL,
  `class_id` int(11) NOT NULL,
  `kind` char(1) COLLATE utf8mb4_bin NOT NULL,
  `exported` tinyint(1) NOT NULL,
  `permission` int(11) DEFAULT NULL,
  `missing` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `EntryPoints`
--

CREATE TABLE `EntryPoints` (
  `id` int(11) NOT NULL,
  `class_id` int(11) DEFAULT NULL,
  `method` varchar(512) DEFAULT NULL,
  `instruction` int(11) DEFAULT NULL,
  `statement` varchar(512) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `ExitPointComponents`
--

CREATE TABLE `ExitPointComponents` (
  `id` int(11) NOT NULL,
  `exit_id` int(11) NOT NULL,
  `component_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `ExitPoints`
--

CREATE TABLE `ExitPoints` (
  `id` int(11) NOT NULL,
  `class_id` int(11) NOT NULL,
  `method` varchar(512) COLLATE utf8mb4_bin NOT NULL,
  `instruction` mediumint(9) NOT NULL,
  `statement` varchar(512) COLLATE utf8mb4_bin DEFAULT NULL,
  `exit_kind` char(1) COLLATE utf8mb4_bin NOT NULL,
  `missing` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `ICCEntryLeaks`
--

CREATE TABLE `ICCEntryLeaks` (
  `id` int(11) NOT NULL,
  `entry_point_id` int(11) DEFAULT NULL,
  `leak_source` varchar(512) NOT NULL,
  `leak_sink` varchar(512) DEFAULT NULL,
  `leak_path` mediumtext,
  `sink_method` varchar(127) DEFAULT NULL,
  `disabled` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `ICCExitLeaks`
--

CREATE TABLE `ICCExitLeaks` (
  `id` int(11) NOT NULL,
  `exit_point_id` int(11) DEFAULT NULL,
  `leak_source` varchar(512) DEFAULT NULL,
  `leak_path` mediumtext,
  `leak_sink` varchar(512) DEFAULT NULL,
  `method` varchar(512) DEFAULT NULL,
  `disabled` tinyint(4) DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `IFilterActions`
--

CREATE TABLE `IFilterActions` (
  `id` int(11) NOT NULL,
  `filter_id` int(11) NOT NULL,
  `action` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IFilterCategories`
--

CREATE TABLE `IFilterCategories` (
  `id` int(11) NOT NULL,
  `filter_id` int(11) NOT NULL,
  `category` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IFilterData`
--

CREATE TABLE `IFilterData` (
  `id` int(11) NOT NULL,
  `filter_id` int(11) DEFAULT NULL,
  `scheme` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `host` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `port` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `path` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `type` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `subtype` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentActions`
--

CREATE TABLE `IntentActions` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `action` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentCategories`
--

CREATE TABLE `IntentCategories` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `category` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentClasses`
--

CREATE TABLE `IntentClasses` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `class` varchar(512) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentData`
--

CREATE TABLE `IntentData` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `data` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentExtras`
--

CREATE TABLE `IntentExtras` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `extra` varchar(512) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentFilters`
--

CREATE TABLE `IntentFilters` (
  `id` int(11) NOT NULL,
  `component_id` int(11) NOT NULL,
  `alias` tinyint(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentMimeTypes`
--

CREATE TABLE `IntentMimeTypes` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `type` varchar(191) COLLATE utf8mb4_bin NOT NULL,
  `subtype` varchar(191) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentPackages`
--

CREATE TABLE `IntentPackages` (
  `id` int(11) NOT NULL,
  `intent_id` int(11) NOT NULL,
  `package` varchar(512) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `IntentPermissions`
--

CREATE TABLE `IntentPermissions` (
  `id` int(11) NOT NULL,
  `exit_id` int(11) NOT NULL,
  `i_permission` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Intents`
--

CREATE TABLE `Intents` (
  `id` int(11) NOT NULL,
  `exit_id` int(11) NOT NULL,
  `implicit` tinyint(1) NOT NULL,
  `alias` tinyint(1) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `ParsedURI`
--

CREATE TABLE `ParsedURI` (
  `id` int(11) NOT NULL DEFAULT '0',
  `scheme` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin,
  `path` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin,
  `host` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin,
  `port` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin,
  `orig_uri` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `PermissionLeaks`
--

CREATE TABLE `PermissionLeaks` (
  `id` int(11) NOT NULL,
  `ICCLeakID` int(11) NOT NULL,
  `PermissionID` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `Permissions`
--

CREATE TABLE `Permissions` (
  `id` int(11) NOT NULL,
  `level` char(1) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `PermissionStrings`
--

CREATE TABLE `PermissionStrings` (
  `id` int(11) NOT NULL,
  `st` varchar(191) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `PrivilegeEscalations`
--

CREATE TABLE `PrivilegeEscalations` (
  `fromapp` int(11) NOT NULL,
  `toapp` int(11) NOT NULL,
  `data_leak_id` int(11) NOT NULL DEFAULT '0',
  `PermissionID` int(11) NOT NULL,
  `icc_type` varchar(10) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `ProviderAuthorities`
--

CREATE TABLE `ProviderAuthorities` (
  `id` int(11) NOT NULL,
  `provider_id` int(11) NOT NULL,
  `authority` varchar(512) COLLATE utf8mb4_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Providers`
--

CREATE TABLE `Providers` (
  `id` int(11) NOT NULL,
  `component_id` int(11) NOT NULL,
  `grant_uri_permissions` tinyint(1) NOT NULL,
  `read_permission` varchar(512) COLLATE utf8mb4_bin DEFAULT NULL,
  `write_permission` varchar(512) COLLATE utf8mb4_bin DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `SensitiveChannels`
--

CREATE TABLE `SensitiveChannels` (
  `fromapp` int(11) NOT NULL,
  `toapp` int(11) NOT NULL,
  `intent_id` int(11) DEFAULT '0',
  `exitpoint` int(11) DEFAULT '0',
  `entryclass` int(11) DEFAULT '0',
  `filter_id` int(11) DEFAULT '0',
  `icc_type` varchar(2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `SourceSinkCount`
--

CREATE TABLE `SourceSinkCount` (
  `id` int(11) NOT NULL,
  `AppID` int(11) NOT NULL,
  `num_Sources` int(11) NOT NULL,
  `num_sinks` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `UriData`
--

CREATE TABLE `UriData` (
  `id` int(11) NOT NULL,
  `scheme` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `ssp` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `uri` longtext COLLATE utf8mb4_bin,
  `path` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL,
  `query` varchar(512) COLLATE utf8mb4_bin DEFAULT NULL,
  `authority` varchar(128) COLLATE utf8mb4_bin DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `Uris`
--

CREATE TABLE `Uris` (
  `id` int(11) NOT NULL,
  `exit_id` int(11) NOT NULL,
  `data` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `UsesPermissions`
--

CREATE TABLE `UsesPermissions` (
  `id` int(11) NOT NULL,
  `app_id` int(11) NOT NULL,
  `uses_permission` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `ActionStrings`
--
ALTER TABLE `ActionStrings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `st` (`st`),
  ADD KEY `st_idx` (`st`) USING HASH;

--
-- Indexes for table `Aliases`
--
ALTER TABLE `Aliases`
  ADD PRIMARY KEY (`id`),
  ADD KEY `component_id` (`component_id`),
  ADD KEY `target_id` (`target_id`);

--
-- Indexes for table `AppAnalysisTime`
--
ALTER TABLE `AppAnalysisTime`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_AppAnalysisTime_1_idx` (`AppID`);

--
-- Indexes for table `AppCategories`
--
ALTER TABLE `AppCategories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_AppCategories_1_idx` (`AppID`),
  ADD KEY `fk_AppCategories_2_idx` (`CategoryID`);

--
-- Indexes for table `Applications`
--
ALTER TABLE `Applications`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `Applications` ADD INDEX(`shasum`);

--
-- Indexes for table `AppTimeout`
--
ALTER TABLE `AppTimeout`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_AppTimeout_1_idx` (`AppID`);

--
-- Indexes for table `Categories`
--
ALTER TABLE `Categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `CategoryStrings`
--
ALTER TABLE `CategoryStrings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `st` (`st`),
  ADD KEY `st_idx` (`st`) USING HASH;

--
-- Indexes for table `Classes`
--
ALTER TABLE `Classes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `app_id_idx` (`app_id`) USING HASH,
  ADD KEY `idx-class` (`class`) USING HASH;

--
-- Indexes for table `ComponentExtras`
--
ALTER TABLE `ComponentExtras`
  ADD PRIMARY KEY (`id`),
  ADD KEY `component_id` (`component_id`);

--
-- Indexes for table `Components`
--
ALTER TABLE `Components`
  ADD PRIMARY KEY (`id`),
  ADD KEY `class_id` (`class_id`),
  ADD KEY `permission` (`permission`);

--
-- Indexes for table `EntryPoints`
--
ALTER TABLE `EntryPoints`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_EntryPoints_class_idx` (`class_id`);

--
-- Indexes for table `ExitPointComponents`
--
ALTER TABLE `ExitPointComponents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `exit_id` (`exit_id`),
  ADD KEY `component_id` (`component_id`);

--
-- Indexes for table `ExitPoints`
--
ALTER TABLE `ExitPoints`
  ADD PRIMARY KEY (`id`),
  ADD KEY `class_id` (`class_id`);

--
-- Indexes for table `ICCEntryLeaks`
--
ALTER TABLE `ICCEntryLeaks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_ICCEntryDataLeaks_entry_idx` (`entry_point_id`);

--
-- Indexes for table `ICCExitLeaks`
--
ALTER TABLE `ICCExitLeaks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_ExitLeaks_exitpoint_idx` (`exit_point_id`);

--
-- Indexes for table `IFilterActions`
--
ALTER TABLE `IFilterActions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `filter_id` (`filter_id`),
  ADD KEY `action_idx` (`action`) USING HASH;

--
-- Indexes for table `IFilterCategories`
--
ALTER TABLE `IFilterCategories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `filter_id` (`filter_id`),
  ADD KEY `category_idx` (`category`) USING HASH;

--
-- Indexes for table `IFilterData`
--
ALTER TABLE `IFilterData`
  ADD PRIMARY KEY (`id`),
  ADD KEY `filter_id` (`filter_id`);

--
-- Indexes for table `IntentActions`
--
ALTER TABLE `IntentActions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `action` (`action`);

--
-- Indexes for table `IntentCategories`
--
ALTER TABLE `IntentCategories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `category` (`category`);

--
-- Indexes for table `IntentClasses`
--
ALTER TABLE `IntentClasses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `iclass-class-idx` (`class`(191)) USING HASH;

--
-- Indexes for table `IntentData`
--
ALTER TABLE `IntentData`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `IntentData_ibfk_2` (`data`);

--
-- Indexes for table `IntentExtras`
--
ALTER TABLE `IntentExtras`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`);

--
-- Indexes for table `IntentFilters`
--
ALTER TABLE `IntentFilters`
  ADD PRIMARY KEY (`id`),
  ADD KEY `c_id_idx` (`component_id`) USING HASH;

--
-- Indexes for table `IntentMimeTypes`
--
ALTER TABLE `IntentMimeTypes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `type_idx` (`type`),
  ADD KEY `subtype_idx` (`subtype`);

--
-- Indexes for table `IntentPackages`
--
ALTER TABLE `IntentPackages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `idx-package` (`package`(191)) USING HASH;

--
-- Indexes for table `IntentPermissions`
--
ALTER TABLE `IntentPermissions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `exit_id` (`exit_id`),
  ADD KEY `i_permission` (`i_permission`);

--
-- Indexes for table `Intents`
--
ALTER TABLE `Intents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `exit_id` (`exit_id`);

--
-- Indexes for table `ParsedURI`
--
ALTER TABLE `ParsedURI`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx-scheme-host` (`host`(10)),
  ADD KEY `idx-path-uri` (`path`(10)),
  ADD KEY `idx-scheme-pUri` (`scheme`(10)) USING BTREE,
  ADD KEY `idx-orig-uri` (`orig_uri`(32));

--
-- Indexes for table `PermissionLeaks`
--
ALTER TABLE `PermissionLeaks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `FK1_leaks_permission` (`PermissionID`),
  ADD KEY `FK2_ICC_permission` (`ICCLeakID`);

--
-- Indexes for table `Permissions`
--
ALTER TABLE `Permissions`
  ADD PRIMARY KEY (`id`,`level`);

--
-- Indexes for table `PermissionStrings`
--
ALTER TABLE `PermissionStrings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `st` (`st`),
  ADD KEY `st_idx` (`st`) USING HASH;

--
-- Indexes for table `PrivilegeEscalations`
--
ALTER TABLE `PrivilegeEscalations`
  ADD KEY `data_leak_id` (`data_leak_id`),
  ADD KEY `PermissionID` (`PermissionID`),
  ADD KEY `toapp` (`toapp`),
  ADD KEY `fromapp` (`fromapp`);

--
-- Indexes for table `ProviderAuthorities`
--
ALTER TABLE `ProviderAuthorities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `provider_id` (`provider_id`);

--
-- Indexes for table `Providers`
--
ALTER TABLE `Providers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `component_id` (`component_id`);

--
-- Indexes for table `SensitiveChannels`
--
ALTER TABLE `SensitiveChannels`
  ADD KEY `fromapp` (`fromapp`),
  ADD KEY `toapp` (`toapp`),
  ADD KEY `intent_id` (`intent_id`),
  ADD KEY `exitpoint` (`exitpoint`),
  ADD KEY `entryclass` (`entryclass`),
  ADD KEY `filter_id` (`filter_id`);

--
-- Indexes for table `SourceSinkCount`
--
ALTER TABLE `SourceSinkCount`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `UriData`
--
ALTER TABLE `UriData`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `Uris`
--
ALTER TABLE `Uris`
  ADD PRIMARY KEY (`id`),
  ADD KEY `exit_id` (`exit_id`),
  ADD KEY `data` (`data`);

--
-- Indexes for table `UsesPermissions`
--
ALTER TABLE `UsesPermissions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `app_id` (`app_id`),
  ADD KEY `uses_permission_idx` (`uses_permission`) USING HASH;

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `ActionStrings`
--
ALTER TABLE `ActionStrings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;
--
-- AUTO_INCREMENT for table `Aliases`
--
ALTER TABLE `Aliases`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `AppAnalysisTime`
--
ALTER TABLE `AppAnalysisTime`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;
--
-- AUTO_INCREMENT for table `AppCategories`
--
ALTER TABLE `AppCategories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;
--
-- AUTO_INCREMENT for table `Applications`
--
ALTER TABLE `Applications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;
--
-- AUTO_INCREMENT for table `AppTimeout`
--
ALTER TABLE `AppTimeout`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `Categories`
--
ALTER TABLE `Categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `CategoryStrings`
--
ALTER TABLE `CategoryStrings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `Classes`
--
ALTER TABLE `Classes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=39;
--
-- AUTO_INCREMENT for table `ComponentExtras`
--
ALTER TABLE `ComponentExtras`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;
--
-- AUTO_INCREMENT for table `Components`
--
ALTER TABLE `Components`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=39;
--
-- AUTO_INCREMENT for table `EntryPoints`
--
ALTER TABLE `EntryPoints`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `ExitPointComponents`
--
ALTER TABLE `ExitPointComponents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;
--
-- AUTO_INCREMENT for table `ExitPoints`
--
ALTER TABLE `ExitPoints`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;
--
-- AUTO_INCREMENT for table `ICCEntryLeaks`
--
ALTER TABLE `ICCEntryLeaks`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `ICCExitLeaks`
--
ALTER TABLE `ICCExitLeaks`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `IFilterActions`
--
ALTER TABLE `IFilterActions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;
--
-- AUTO_INCREMENT for table `IFilterCategories`
--
ALTER TABLE `IFilterCategories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;
--
-- AUTO_INCREMENT for table `IFilterData`
--
ALTER TABLE `IFilterData`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `IntentActions`
--
ALTER TABLE `IntentActions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `IntentCategories`
--
ALTER TABLE `IntentCategories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `IntentClasses`
--
ALTER TABLE `IntentClasses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;
--
-- AUTO_INCREMENT for table `IntentData`
--
ALTER TABLE `IntentData`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `IntentExtras`
--
ALTER TABLE `IntentExtras`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;
--
-- AUTO_INCREMENT for table `IntentFilters`
--
ALTER TABLE `IntentFilters`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;
--
-- AUTO_INCREMENT for table `IntentMimeTypes`
--
ALTER TABLE `IntentMimeTypes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `IntentPackages`
--
ALTER TABLE `IntentPackages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;
--
-- AUTO_INCREMENT for table `IntentPermissions`
--
ALTER TABLE `IntentPermissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
--
-- AUTO_INCREMENT for table `Intents`
--
ALTER TABLE `Intents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;
--
-- AUTO_INCREMENT for table `PermissionLeaks`
--
ALTER TABLE `PermissionLeaks`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `PermissionStrings`
--
ALTER TABLE `PermissionStrings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `ProviderAuthorities`
--
ALTER TABLE `ProviderAuthorities`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `Providers`
--
ALTER TABLE `Providers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT for table `SourceSinkCount`
--
ALTER TABLE `SourceSinkCount`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `UriData`
--
ALTER TABLE `UriData`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `Uris`
--
ALTER TABLE `Uris`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT for table `UsesPermissions`
--
ALTER TABLE `UsesPermissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;
--
-- Constraints for dumped tables
--

--
-- Constraints for table `Aliases`
--
ALTER TABLE `Aliases`
  ADD CONSTRAINT `Aliases_ibfk_1` FOREIGN KEY (`component_id`) REFERENCES `Components` (`id`),
  ADD CONSTRAINT `Aliases_ibfk_2` FOREIGN KEY (`target_id`) REFERENCES `Components` (`id`);

--
-- Constraints for table `AppAnalysisTime`
--
ALTER TABLE `AppAnalysisTime`
  ADD CONSTRAINT `fk_AppAnalysisTime_1` FOREIGN KEY (`AppID`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `AppCategories`
--
ALTER TABLE `AppCategories`
  ADD CONSTRAINT `fk_AppCategories_1` FOREIGN KEY (`AppID`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_AppCategories_2` FOREIGN KEY (`CategoryID`) REFERENCES `Categories` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `AppTimeout`
--
ALTER TABLE `AppTimeout`
  ADD CONSTRAINT `fk_AppTimeout_1` FOREIGN KEY (`AppID`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `Classes`
--
ALTER TABLE `Classes`
  ADD CONSTRAINT `Classes_ibfk_1` FOREIGN KEY (`app_id`) REFERENCES `Applications` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ComponentExtras`
--
ALTER TABLE `ComponentExtras`
  ADD CONSTRAINT `ComponentExtras_ibfk_1` FOREIGN KEY (`component_id`) REFERENCES `Components` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `Components`
--
ALTER TABLE `Components`
  ADD CONSTRAINT `Components_ibfk_1` FOREIGN KEY (`class_id`) REFERENCES `Classes` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Components_ibfk_2` FOREIGN KEY (`permission`) REFERENCES `PermissionStrings` (`id`);

--
-- Constraints for table `EntryPoints`
--
ALTER TABLE `EntryPoints`
  ADD CONSTRAINT `fk_EntryPoints_class` FOREIGN KEY (`class_id`) REFERENCES `Classes` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `ExitPointComponents`
--
ALTER TABLE `ExitPointComponents`
  ADD CONSTRAINT `ExitPointComponents_ibfk_1` FOREIGN KEY (`exit_id`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `ExitPointComponents_ibfk_2` FOREIGN KEY (`component_id`) REFERENCES `Components` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ExitPoints`
--
ALTER TABLE `ExitPoints`
  ADD CONSTRAINT `ExitPoints_ibfk_1` FOREIGN KEY (`class_id`) REFERENCES `Classes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ICCEntryLeaks`
--
ALTER TABLE `ICCEntryLeaks`
  ADD CONSTRAINT `fk_ICCEntryDataLeaks_entry` FOREIGN KEY (`entry_point_id`) REFERENCES `EntryPoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `ICCExitLeaks`
--
ALTER TABLE `ICCExitLeaks`
  ADD CONSTRAINT `fk_ExitLeaks_exitpoint` FOREIGN KEY (`exit_point_id`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `IFilterActions`
--
ALTER TABLE `IFilterActions`
  ADD CONSTRAINT `IFilterActions_ibfk_1` FOREIGN KEY (`filter_id`) REFERENCES `IntentFilters` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `IFilterActions_ibfk_2` FOREIGN KEY (`action`) REFERENCES `ActionStrings` (`id`);

--
-- Constraints for table `IFilterCategories`
--
ALTER TABLE `IFilterCategories`
  ADD CONSTRAINT `IFilterCategories_ibfk_1` FOREIGN KEY (`filter_id`) REFERENCES `IntentFilters` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `IFilterCategories_ibfk_2` FOREIGN KEY (`category`) REFERENCES `CategoryStrings` (`id`);

--
-- Constraints for table `IFilterData`
--
ALTER TABLE `IFilterData`
  ADD CONSTRAINT `IFilterData_ibfk_1` FOREIGN KEY (`filter_id`) REFERENCES `IntentFilters` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentActions`
--
ALTER TABLE `IntentActions`
  ADD CONSTRAINT `IntentActions_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `IntentActions_ibfk_2` FOREIGN KEY (`action`) REFERENCES `ActionStrings` (`id`);

--
-- Constraints for table `IntentCategories`
--
ALTER TABLE `IntentCategories`
  ADD CONSTRAINT `IntentCategories_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `IntentCategories_ibfk_2` FOREIGN KEY (`category`) REFERENCES `CategoryStrings` (`id`);

--
-- Constraints for table `IntentClasses`
--
ALTER TABLE `IntentClasses`
  ADD CONSTRAINT `IntentClasses_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentData`
--
ALTER TABLE `IntentData`
  ADD CONSTRAINT `IntentData_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentExtras`
--
ALTER TABLE `IntentExtras`
  ADD CONSTRAINT `IntentExtras_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentFilters`
--
ALTER TABLE `IntentFilters`
  ADD CONSTRAINT `IntentFilters_ibfk_1` FOREIGN KEY (`component_id`) REFERENCES `Components` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentMimeTypes`
--
ALTER TABLE `IntentMimeTypes`
  ADD CONSTRAINT `IMimeTypes_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentPackages`
--
ALTER TABLE `IntentPackages`
  ADD CONSTRAINT `IntentPackages_ibfk_1` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `IntentPermissions`
--
ALTER TABLE `IntentPermissions`
  ADD CONSTRAINT `IntentPermissions_ibfk_1` FOREIGN KEY (`exit_id`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `IntentPermissions_ibfk_2` FOREIGN KEY (`i_permission`) REFERENCES `PermissionStrings` (`id`);

--
-- Constraints for table `Intents`
--
ALTER TABLE `Intents`
  ADD CONSTRAINT `Intents_ibfk_1` FOREIGN KEY (`exit_id`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `PermissionLeaks`
--
ALTER TABLE `PermissionLeaks`
  ADD CONSTRAINT `FK1_leaks_permission` FOREIGN KEY (`PermissionID`) REFERENCES `PermissionStrings` (`id`),
  ADD CONSTRAINT `FK2_ICC_permission` FOREIGN KEY (`ICCLeakID`) REFERENCES `ICCExitLeaks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `Permissions`
--
ALTER TABLE `Permissions`
  ADD CONSTRAINT `Permissions_ibfk_1` FOREIGN KEY (`id`) REFERENCES `PermissionStrings` (`id`);

--
-- Constraints for table `PrivilegeEscalations`
--
ALTER TABLE `PrivilegeEscalations`
  ADD CONSTRAINT `FK_PrivilegeEscalations_Applications` FOREIGN KEY (`fromapp`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_PrivilegeEscalations_Applications_2` FOREIGN KEY (`toapp`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_PrivilegeEscalations_ICCExitLeaks` FOREIGN KEY (`data_leak_id`) REFERENCES `ICCExitLeaks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_PrivilegeEscalations_PermissionStrings` FOREIGN KEY (`PermissionID`) REFERENCES `PermissionStrings` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `ProviderAuthorities`
--
ALTER TABLE `ProviderAuthorities`
  ADD CONSTRAINT `PAuthorities_ibfk_1` FOREIGN KEY (`provider_id`) REFERENCES `Providers` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `Providers`
--
ALTER TABLE `Providers`
  ADD CONSTRAINT `Providers_ibfk_1` FOREIGN KEY (`component_id`) REFERENCES `Components` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `SensitiveChannels`
--
ALTER TABLE `SensitiveChannels`
  ADD CONSTRAINT `FK_SensitiveChannels_Applications` FOREIGN KEY (`fromapp`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_SensitiveChannels_Applications_2` FOREIGN KEY (`toapp`) REFERENCES `Applications` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_SensitiveChannels_Classes` FOREIGN KEY (`entryclass`) REFERENCES `Classes` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_SensitiveChannels_ExitPoints` FOREIGN KEY (`exitpoint`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_SensitiveChannels_Intents` FOREIGN KEY (`intent_id`) REFERENCES `Intents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `Uris`
--
ALTER TABLE `Uris`
  ADD CONSTRAINT `Uris_ibfk_1` FOREIGN KEY (`exit_id`) REFERENCES `ExitPoints` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Uris_ibfk_2` FOREIGN KEY (`data`) REFERENCES `UriData` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `UsesPermissions`
--
ALTER TABLE `UsesPermissions`
  ADD CONSTRAINT `UsesPermissions_ibfk_1` FOREIGN KEY (`app_id`) REFERENCES `Applications` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `UsesPermissions_ibfk_2` FOREIGN KEY (`uses_permission`) REFERENCES `PermissionStrings` (`id`);

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
