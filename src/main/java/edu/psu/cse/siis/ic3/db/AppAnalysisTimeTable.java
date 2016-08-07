package edu.psu.cse.siis.ic3.db;

import java.sql.SQLException;

public class AppAnalysisTimeTable extends Table {
  private static final String INSERT =
      "INSERT INTO AppAnalysisTime (`AppID`, `ModelParse`, `ClassLoad`, `MainGeneration`, `EntryPointMapping`, `IC3TotalTime`, "
          + "`ExitPointPath`, `EntryPointPath`, `TotalTime`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);";
  private static final String FIND = "SELECT id FROM AppAnalysisTime WHERE AppID = ?";
  private static final String DELETE = "DELETE FROM AppAnalysisTime WHERE AppID = ?";

  public int insert(int app, long modelParseTime, long classLoadTime, long mainGenerationTime,
      long entryPointMappingTime, long ic3Time, long entryPathTime, long exitPathTime,
      long totalTime) throws SQLException {
    delete(app);

    insertStatement = getConnection().prepareStatement(INSERT);

    insertStatement.setInt(1, app);
    insertStatement.setLong(2, modelParseTime);
    insertStatement.setLong(3, classLoadTime);
    insertStatement.setLong(4, mainGenerationTime);
    insertStatement.setLong(5, entryPointMappingTime);
    insertStatement.setLong(6, ic3Time);
    insertStatement.setLong(7, entryPathTime);
    insertStatement.setLong(8, exitPathTime);
    insertStatement.setLong(9, totalTime);

    if (insertStatement.executeUpdate() == 0) {
      return NOT_FOUND;
    }

    return findAutoIncrement();
  }

  public void delete(int app) throws SQLException {
    findStatement = getConnection().prepareStatement(DELETE);
    findStatement.setInt(1, app);

    findStatement.executeUpdate();
    findStatement.close();

  }
}
