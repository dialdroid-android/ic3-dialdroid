/*******************************************************************************
 * Copyright (c) 2012 Secure Software Engineering Group at EC SPRIDE.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Lesser Public License v2.1
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 *
 * Contributors: Christian Fritz, Steven Arzt, Siegfried Rasthofer, Eric
 * Bodden, and others.
 ******************************************************************************/
package edu.psu.cse.siis.ic3;

import java.io.File;
import java.io.IOException;
import java.security.CodeSource;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import soot.Main;
import soot.PackManager;
import soot.Scene;
import soot.SootClass;
import soot.SootMethod;
import soot.jimple.infoflow.AbstractInfoflow;
import soot.jimple.infoflow.android.AnalyzeJimpleClass;
import soot.jimple.infoflow.android.InfoflowAndroidConfiguration;
import soot.jimple.infoflow.android.callbacks.AbstractCallbackAnalyzer;
import soot.jimple.infoflow.android.callbacks.DefaultCallbackAnalyzer;
import soot.jimple.infoflow.android.config.SootConfigForAndroid;
import soot.jimple.infoflow.android.data.AndroidMethod;
import soot.jimple.infoflow.android.resources.ARSCFileParser;
import soot.jimple.infoflow.android.resources.ARSCFileParser.AbstractResource;
import soot.jimple.infoflow.android.resources.ARSCFileParser.StringResource;
import soot.jimple.infoflow.android.resources.LayoutControl;
import soot.jimple.infoflow.android.resources.LayoutFileParser;
import soot.jimple.infoflow.config.IInfoflowConfig;
import soot.jimple.infoflow.data.SootMethodAndClass;
import soot.jimple.infoflow.entryPointCreators.AndroidEntryPointCreator;
import soot.options.Options;

public class SetupApplication {

  private final Logger logger = LoggerFactory.getLogger(getClass());

  private final Map<String, Set<SootMethodAndClass>> callbackMethods =
      new HashMap<String, Set<SootMethodAndClass>>(10000);

  private Set<String> entrypoints = null;
  private final Set<String> callbackClasses = null;
  private String appPackageName = "";
  private final String callbackFile = "AndroidCallbacks.txt";

  private final String apkFileLocation;
  private final String classDirectory;
  private final String androidClassPath;
  private final InfoflowAndroidConfiguration config = new InfoflowAndroidConfiguration();
  private final IInfoflowConfig sootConfig = new SootConfigForAndroid();

  private AndroidEntryPointCreator entryPointCreator;

  public SetupApplication(String apkFileLocation, String classDirectory, String androidClassPath) {
    this.apkFileLocation = apkFileLocation;
    this.classDirectory = classDirectory;
    this.androidClassPath = androidClassPath;
  }

  /**
   * Gets the entry point creator used for generating the dummy main method emulating the Android
   * lifecycle and the callbacks. Make sure to call calculateSourcesSinksEntryPoints() first, or you
   * will get a null result.
   *
   * @return The entry point creator
   */
  public AndroidEntryPointCreator getEntryPointCreator() {
    return entryPointCreator;
  }

  /**
   * Prints list of classes containing entry points to stdout
   */
  public void printEntrypoints() {
    if (logger.isDebugEnabled()) {
      if (this.entrypoints == null) {
        logger.debug("Entry points not initialized");
      } else {
        logger.debug("Classes containing entry points:");
        for (String className : entrypoints) {
          logger.debug("\t" + className);
        }
        logger.debug("End of Entrypoints");
      }
    }
  }

  private void calculateCallbackMethods(ARSCFileParser resParser, LayoutFileParser lfp)
      throws IOException {
    AbstractCallbackAnalyzer jimpleClass = null;

    boolean hasChanged = true;
    while (hasChanged) {
      hasChanged = false;

      // Create the new iteration of the main method
      soot.G.reset();
      initializeSoot(true);
      createMainMethod();

      if (jimpleClass == null) {
        // Collect the callback interfaces implemented in the app's
        // source code
        jimpleClass =
            callbackClasses == null ? new DefaultCallbackAnalyzer(config, entrypoints, callbackFile)
                : new DefaultCallbackAnalyzer(config, entrypoints, callbackClasses);
        jimpleClass.collectCallbackMethods();

        // Find the user-defined sources in the layout XML files. This
        // only needs to be done once, but is a Soot phase.
        lfp.parseLayoutFile(apkFileLocation);
      } else {
        jimpleClass.collectCallbackMethodsIncremental();
      }

      // Run the soot-based operations
      PackManager.v().getPack("wjpp").apply();
      PackManager.v().getPack("cg").apply();
      PackManager.v().getPack("wjtp").apply();

      // Collect the results of the soot-based phases
      for (Entry<String, Set<SootMethodAndClass>> entry : jimpleClass.getCallbackMethods()
          .entrySet()) {
        Set<SootMethodAndClass> curCallbacks = this.callbackMethods.get(entry.getKey());
        if (curCallbacks != null) {
          if (curCallbacks.addAll(entry.getValue())) {
            hasChanged = true;
          }
        } else {
          this.callbackMethods.put(entry.getKey(), new HashSet<>(entry.getValue()));
          hasChanged = true;
        }
      }

      if (entrypoints.addAll(jimpleClass.getDynamicManifestComponents())) {
        hasChanged = true;
      }
    }

    // Collect the XML-based callback methods
    collectXmlBasedCallbackMethods(resParser, lfp, jimpleClass);
  }

  /**
   * Collects the XML-based callback methods, e.g., Button.onClick() declared in layout XML files
   *
   * @param resParser The ARSC resource parser
   * @param lfp The layout file parser
   * @param jimpleClass The analysis class that gives us a mapping between layout IDs and components
   */
  private void collectXmlBasedCallbackMethods(ARSCFileParser resParser, LayoutFileParser lfp,
      AbstractCallbackAnalyzer jimpleClass) {
    // Collect the XML-based callback methods
    for (Entry<String, Set<Integer>> lcentry : jimpleClass.getLayoutClasses().entrySet()) {
      final SootClass callbackClass = Scene.v().getSootClass(lcentry.getKey());

      for (Integer classId : lcentry.getValue()) {
        AbstractResource resource = resParser.findResource(classId);
        if (resource instanceof StringResource) {
          final String layoutFileName = ((StringResource) resource).getValue();

          // Add the callback methods for the given class
          Set<String> callbackMethods = lfp.getCallbackMethods().get(layoutFileName);
          if (callbackMethods != null) {
            for (String methodName : callbackMethods) {
              final String subSig = "void " + methodName + "(android.view.View)";

              // The callback may be declared directly in the
              // class
              // or in one of the superclasses
              SootClass currentClass = callbackClass;
              while (true) {
                SootMethod callbackMethod = currentClass.getMethodUnsafe(subSig);
                if (callbackMethod != null) {
                  addCallbackMethod(callbackClass.getName(), new AndroidMethod(callbackMethod));
                  break;
                }
                if (!currentClass.hasSuperclass()) {
                  System.err.println("Callback method " + methodName + " not found in class "
                      + callbackClass.getName());
                  break;
                }
                currentClass = currentClass.getSuperclass();
              }
            }
          }

          // For user-defined views, we need to emulate their
          // callbacks
          Set<LayoutControl> controls = lfp.getUserControls().get(layoutFileName);
          if (controls != null) {
            for (LayoutControl lc : controls) {
              registerCallbackMethodsForView(callbackClass, lc);
            }
          }
        } else {
          System.err.println("Unexpected resource type for layout class");
        }
      }
    }

    // Add the callback methods as sources and sinks
    {
      Set<SootMethodAndClass> callbacksPlain = new HashSet<SootMethodAndClass>();
      for (Set<SootMethodAndClass> set : this.callbackMethods.values()) {
        callbacksPlain.addAll(set);
      }
      System.out.println("Found " + callbacksPlain.size() + " callback methods for "
          + this.callbackMethods.size() + " components");
    }
  }

  /**
   * Calculates the sets of sources, modifiers, entry points, and callbacks methods for the given
   * APK file.
   *
   * @param sourceMethods The set of methods to be considered as sources
   * @param modifierMethods The set of methods to be considered as modifiers
   * @throws IOException Thrown if the given source/modifier file could not be read.
   */
  public Map<String, Set<String>> calculateSourcesSinksEntrypoints(Set<AndroidMethod> sourceMethods,
      Set<AndroidMethod> modifierMethods, String packageName, Set<String> entryPointClasses)
      throws IOException {
    // To look for callbacks, we need to start somewhere. We use the Android
    // lifecycle methods for this purpose.
    this.appPackageName = packageName;
    this.entrypoints = entryPointClasses;

    boolean parseLayoutFile = !apkFileLocation.endsWith(".xml");

    // Parse the resource file
    ARSCFileParser resParser = null;
    if (parseLayoutFile) {
      resParser = new ARSCFileParser();
      resParser.parse(apkFileLocation);
    }

    AnalyzeJimpleClass jimpleClass = null;
    LayoutFileParser lfp =
        parseLayoutFile ? new LayoutFileParser(this.appPackageName, resParser) : null;

    calculateCallbackMethods(resParser, lfp);

    logger.info("Entry point calculation done.");

    // Clean up everything we no longer need
    soot.G.reset();

    Map<String, Set<String>> result = new HashMap<>(this.callbackMethods.size());
    for (Map.Entry<String, Set<SootMethodAndClass>> entry : this.callbackMethods.entrySet()) {
      Set<SootMethodAndClass> callbackSet = entry.getValue();
      Set<String> callbackStrings = new HashSet<>(callbackSet.size());

      for (SootMethodAndClass androidMethod : callbackSet) {
        callbackStrings.add(androidMethod.getSignature());
      }

      result.put(entry.getKey(), callbackStrings);
    }

    entryPointCreator = createEntryPointCreator();

    return result;
  }

  /**
   * Registers the callback methods in the given layout control so that they are included in the
   * dummy main method
   *
   * @param callbackClass The class with which to associate the layout callbacks
   * @param lc The layout control whose callbacks are to be associated with the given class
   */
  private void registerCallbackMethodsForView(SootClass callbackClass, LayoutControl lc) {
    // Ignore system classes
    if (callbackClass.getName().startsWith("android.")) {
      return;
    }
    if (lc.getViewClass().getName().startsWith("android.")) {
      return;
    }

    // Check whether the current class is actually a view
    {
      SootClass sc = lc.getViewClass();
      boolean isView = false;
      while (sc.hasSuperclass()) {
        if (sc.getName().equals("android.view.View")) {
          isView = true;
          break;
        }
        sc = sc.getSuperclass();
      }
      if (!isView) {
        return;
      }
    }

    // There are also some classes that implement interesting callback
    // methods.
    // We model this as follows: Whenever the user overwrites a method in an
    // Android OS class, we treat it as a potential callback.
    SootClass sc = lc.getViewClass();
    Set<String> systemMethods = new HashSet<String>(10000);
    for (SootClass parentClass : Scene.v().getActiveHierarchy().getSuperclassesOf(sc)) {
      if (parentClass.getName().startsWith("android.")) {
        for (SootMethod sm : parentClass.getMethods()) {
          if (!sm.isConstructor()) {
            systemMethods.add(sm.getSubSignature());
          }
        }
      }
    }

    // Scan for methods that overwrite parent class methods
    for (SootMethod sm : sc.getMethods()) {
      if (!sm.isConstructor()) {
        if (systemMethods.contains(sm.getSubSignature())) {
          // This is a real callback method
          addCallbackMethod(callbackClass.getName(), new AndroidMethod(sm));
        }
      }
    }
  }

  /**
   * Adds a method to the set of callback method
   *
   * @param layoutClass The layout class for which to register the callback
   * @param callbackMethod The callback method to register
   */
  private void addCallbackMethod(String layoutClass, AndroidMethod callbackMethod) {
    Set<SootMethodAndClass> methods = this.callbackMethods.get(layoutClass);
    if (methods == null) {
      methods = new HashSet<SootMethodAndClass>();
      this.callbackMethods.put(layoutClass, methods);
    }
    methods.add(new AndroidMethod(callbackMethod));
  }

  /**
   * Creates the main method based on the current callback information, injects it into the Soot
   * scene.
   */
  private void createMainMethod() {
    // Always update the entry point creator to reflect the newest set
    // of callback methods
    SootMethod entryPoint = createEntryPointCreator().createDummyMain();
    Scene.v().setEntryPoints(Collections.singletonList(entryPoint));
    if (Scene.v().containsClass(entryPoint.getDeclaringClass().getName())) {
      Scene.v().removeClass(entryPoint.getDeclaringClass());
    }
    Scene.v().addClass(entryPoint.getDeclaringClass());
  }

  /**
   * Initializes soot for running the soot-based phases of the application metadata analysis
   *
   * @return The entry point used for running soot
   */
  public void initializeSoot() {
    soot.G.reset();

    Options.v().set_ignore_resolution_errors(true);
    Options.v().set_debug(false);
    Options.v().set_verbose(false);
    Options.v().set_unfriendly_mode(true);

    Options.v().set_no_bodies_for_excluded(true);
    Options.v().set_allow_phantom_refs(true);
    Options.v().set_output_format(Options.output_format_none);
    Options.v().set_whole_program(true);
    Options.v().setPhaseOption("cg.spark", "on");
    // Options.v().setPhaseOption("cg.spark", "geom-pta:true");
    // Options.v().setPhaseOption("cg.spark", "geom-encoding:PtIns");
    Options.v().set_ignore_resolution_errors(true);
    // Options.v().setPhaseOption("jb", "use-original-names:true");
    Options.v()
        .set_soot_classpath(this.apkFileLocation + File.pathSeparator + this.androidClassPath);
    if (logger.isDebugEnabled()) {
      logger.debug("Android class path: " + this.androidClassPath);
    }
    
        
    Options.v().set_force_android_jar("ic3-android.jar");
    // Options.v().set_src_prec(Options.src_prec_apk);

    Options.v().set_src_prec(Options.src_prec_apk);
    // soot.options.Options.v().set_process_dir(Collections.singletonList(this.apkFileLocation));
    // soot.options.Options.v().set_force_android_jar("./android.jar");

    Options.v().set_process_dir(new ArrayList<>(this.entrypoints));
    // Options.v().set_app(true);
    Main.v().autoSetOptions();

    Scene.v().loadNecessaryClasses();

    // for (String className : this.entrypoints) {
    // SootClass c = Scene.v().forceResolve(className, SootClass.BODIES);
    // c.setApplicationClass();
    // }
    //
    // SootMethod entryPoint = getEntryPointCreator().createDummyMain();
    // Scene.v().setEntryPoints(Collections.singletonList(entryPoint));
    // return entryPoint;
  }

  /**
   * Builds the classpath for this analysis
   *
   * @return The classpath to be used for the taint analysis
   */
  private String getClasspath() {
    boolean forceAndroidJar = false;

    String classpath = forceAndroidJar ? androidClassPath
        : Scene.v().getAndroidJarPath(androidClassPath, apkFileLocation);

    logger.debug("soot classpath: " + classpath);
    return classpath;
  }

  /**
   * Initializes soot for running the soot-based phases of the application metadata analysis
   *
   * @param constructCallgraph True if a callgraph shall be constructed, otherwise false
   */
  private void initializeSoot(boolean constructCallgraph) {
    Options.v().set_no_bodies_for_excluded(true);
    Options.v().set_allow_phantom_refs(true);
    Options.v().set_output_format(Options.output_format_none);
    Options.v().set_whole_program(constructCallgraph);
    Options.v().set_process_dir(Collections.singletonList(apkFileLocation));
    Options.v().set_soot_classpath(getClasspath());

    Options.v().set_src_prec(Options.src_prec_apk_class_jimple);
    Options.v().set_keep_line_number(false);
    Options.v().set_keep_offset(false);
    Main.v().autoSetOptions();

    // Set the Soot configuration options
    if (sootConfig != null) {
      sootConfig.setSootOptions(Options.v());
    }

    // Configure the callgraph algorithm
    if (constructCallgraph) {
      switch (config.getCallgraphAlgorithm()) {
        case AutomaticSelection:
        case SPARK:
          Options.v().setPhaseOption("cg.spark", "on");
          break;
        case GEOM:
          Options.v().setPhaseOption("cg.spark", "on");
          AbstractInfoflow.setGeomPtaSpecificOptions();
          break;
        case CHA:
          Options.v().setPhaseOption("cg.cha", "on");
          break;
        case RTA:
          Options.v().setPhaseOption("cg.spark", "on");
          Options.v().setPhaseOption("cg.spark", "rta:true");
          Options.v().setPhaseOption("cg.spark", "on-fly-cg:false");
          break;
        case VTA:
          Options.v().setPhaseOption("cg.spark", "on");
          Options.v().setPhaseOption("cg.spark", "vta:true");
          break;
        default:
          throw new RuntimeException("Invalid callgraph algorithm");
      }
    }

    // Load whetever we need
    Scene.v().loadNecessaryClasses();
  }

  public AndroidEntryPointCreator createEntryPointCreator() {
    AndroidEntryPointCreator entryPointCreator =
        new AndroidEntryPointCreator(new ArrayList<String>(this.entrypoints));
    Map<String, List<String>> callbackMethodSigs = new HashMap<String, List<String>>();
    for (String className : this.callbackMethods.keySet()) {
      List<String> methodSigs = new ArrayList<String>();
      callbackMethodSigs.put(className, methodSigs);
      for (SootMethodAndClass am : this.callbackMethods.get(className)) {
        methodSigs.add(am.getSignature());
      }
    }
    entryPointCreator.setCallbackFunctions(callbackMethodSigs);
    return entryPointCreator;
  }
}
