package edu.psu.cse.siis.ic3;


import java.sql.SQLException;

import edu.psu.cse.siis.ic3.db.SQLConnection;
import edu.psu.cse.siis.ic3.manifest.ManifestPullParser;

public class Main {
  public static void main(String[] args) {

    edu.psu.cse.siis.coal.Main.reset();
    SQLConnection.reset();
    


    Ic3CommandLineParser parser = new Ic3CommandLineParser();
    Ic3CommandLineArguments commandLineArguments =
        parser.parseCommandLine(args, Ic3CommandLineArguments.class);
    if (commandLineArguments == null) {
      return;
    }
    commandLineArguments.processCommandLineArguments();
    
    SQLConnection.init(commandLineArguments.getDbName(), "./cc.properties", null, 3306);
    
    ManifestPullParser manifestParser = new ManifestPullParser();
	manifestParser.loadManifestFile(commandLineArguments.getInput());

	try {
		if (SQLConnection.checkIfAppAnalyzed(manifestParser.getPackageName(), manifestParser.getVersion())) {		
			return;
		}
	
    
    Ic3Analysis analysis = new Ic3Analysis(commandLineArguments);
    analysis.performAnalysis(commandLineArguments);
    
	} catch (SQLException e) {
		// TODO Auto-generated catch block
		e.printStackTrace();
	}

  }

}
