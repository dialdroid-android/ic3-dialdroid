# IC3-DIALDroid

IC3-DIALDroid is an updated version of IC3 (http://siis.cse.psu.edu/ic3/). However, in contrast to IC3, 
 - It does not require apk files to be retargeted using DARE (i.e., can directly work on apk files.
 - Due to more accurate lifecycle modeling, it can identify more intents.
 - Due to numerous bug fixes it has less failures.


## Instructions
1. Please download or clone this repository.
2. You can directly use the standalone Jar file (ic3-dialdroid.jar) inside the build directory.
3. Or you can build using ant (ant -d clean compile fullJar).
4. To run IC3-DIALDroid you will need android platform files. You can get a collection here: https://github.com/Sable/android-platforms
5. IC3-DIALDroid stores results in a MySQL database. The database schema is here: https://github.com/dialdroid-ndss/dialdroid-db/blob/master/DIALDroid.sql
6. Please modify the cc.properties file inside the build directory to provide database username and password. 
7. Please note the the cc.properties file, and the AndroidCallbacks.txt must be in the same directory as the ic3-dialdroid.jar.
8.  Use following command to run ic3-dialdroid

: java [JVM options] -jar [path to IC3 Jar] -input [path to apk] -cp [path to Android platforms] -dbname [database_name]

Use JVM options to allocation more memory: e.g., -Xms4G -Xmx16G, will allocate maximum 16GB memory to JVM. 
