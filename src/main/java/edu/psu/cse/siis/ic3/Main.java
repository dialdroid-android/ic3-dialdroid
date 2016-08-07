package edu.psu.cse.siis.ic3;

import edu.psu.cse.siis.ic3.db.SQLConnection;

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
    Ic3Analysis analysis = new Ic3Analysis(commandLineArguments);
    analysis.performAnalysis(commandLineArguments);

  }

}
