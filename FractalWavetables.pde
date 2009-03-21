
/**
 * Drag the mouse over the pattern sliders to create sound. 
 * Add or remove sliders via the "steps" control.
 * <br/><br/>Try setting the number of steps to an interesting metrical unit &#8212; say "8" &#8212; 
 * and use the pattern as a fractal step sequencer.
 * <br/><br/>If the UI freezes, try reloading the page. 
 * <br/><br/>If you like the sounds, you can download and run the app locally to save out files. 
 * <p><a href="http://www.raintone.com/code/processing/FractalWavetables/application.macosx.zip">Mac OS X version</a><br />
 * <a href="http://www.raintone.com/code/processing/FractalWavetables/application.windows.zip">Windows version</a><br />
 * <a href="http://www.raintone.com/code/processing/FractalWavetables/application.linux.zip">Linux version</a></p>
 * <a href="http://www.raintone.com/">Back to Raintone.com</a>
 * <br/></br>
 * <br/><br/>Thanks to Terran Olson's work on <a href="http://www.halfcadence.net/audio-fractals/">audio fractals</a> that inspired this sketch.
 * Thanks to Krister Olsson's <a href="http://www.tree-axis.com/Ess/">Ess library</a> for the sound support.
 * <br/><br/>
 */

// Fractal Wavetables
// March 2009
// jdn (at) raintone.com
//
// change history:
// v1 - basic algorithm and mono saving
// v2 - added drag-and-drop import of fw_xxxx.aif files
// v3 - code cleanup
// v4 - switched to controlP5 library for most of GUI.
//      refactored code -- FWAudio could become class
// v5 - added a, b, stereo a+b and morph a->b modes
//
// 

import krister.Ess.*;  // nice simple sound library
import sojamo.drop.*;
import controlP5.*;  // holy shit this library rocks


/*
 * Model
 */

// Important constants
final int SR = 44100;
final int MAX_SLIDERS = 80;
final int LEFT_MARGIN = 100;

// fractal data
final int NUM_PATTERNS = 2;
FloatFract[] fract = new FloatFract[NUM_PATTERNS];  // to support stereo
int numPatternsActive = 1;
int patternOffset = 1;
boolean morphing = false;

// pattern size / timing data
float curDuration = 0;
int targetIteration = 0;

FWAudio playback;

/*
 * Control
 */

SDrop drop;  // for dropping saved files back into the program to load as "presets"
  
public ControlP5 controlP5;
Slider stepsSlider;
Slider durationSlider;
FWSliderPool[] patternSliders = new FWSliderPool[NUM_PATTERNS];
IterationView[] fractView = new IterationView[NUM_PATTERNS];

ArrayList mouseListeners = new ArrayList();

// create and wire the entire GUI...
void setup() {
  Ess.start(this);
  
  playback = new FWAudio();

  // drag-and-drop handler for file imports
  drop = new SDrop(this);

  size(800, 600);
  colorMode(HSB, 1);
  background(0);
  
  // setup UI controller
  controlP5 = new ControlP5(this);
  
  // mode buttons
  int buttonWidth = 77;
  int buttonHeight = 20;
  int buttonY = 14;
  int b = 1;
  controlP5.addButton("a",1,LEFT_MARGIN,buttonY,buttonWidth,buttonHeight);
  controlP5.addButton("b",1,LEFT_MARGIN+(b++)*(buttonWidth+10),buttonY,buttonWidth,buttonHeight);
  controlP5.addButton("stereo",1,LEFT_MARGIN+(b++)*(buttonWidth+10),buttonY,buttonWidth,buttonHeight).setLabel("stereo a+b");
  controlP5.addButton("morph",1,LEFT_MARGIN+(b++)*(buttonWidth+10),buttonY,buttonWidth,buttonHeight);
  controlP5.addButton("swap",1,LEFT_MARGIN+(b++)*(buttonWidth+10),buttonY,buttonWidth,buttonHeight).setLabel("swap a<->b");
  // save button -- only if we're running as an application
  if(!online) {
    controlP5.addButton("save",1,LEFT_MARGIN+(b++)*(buttonWidth+10),buttonY,buttonWidth,buttonHeight).setLabel("Save Audio");
  }
  
  // horizontal sliders
  stepsSlider = controlP5.addSlider("steps",2,MAX_SLIDERS,3,LEFT_MARGIN,245,width-200,10);
  stepsSlider.setLabel("");
  durationSlider = controlP5.addSlider("duration",0.25,30,4.0,LEFT_MARGIN,275,width-200,10); 
  durationSlider.setLabel("seconds");
  durationSlider.setDecimalPrecision(2);  
  
  // labels
  controlP5.addTextlabel("patternLabel", "pattern", LEFT_MARGIN-43, 121);
  controlP5.addTextlabel("stepsLabel", "steps", LEFT_MARGIN-33, 246);
  controlP5.addTextlabel("durationLabel", "duration", LEFT_MARGIN-47, 276);
  
  controlP5.addTextlabel("1", "1", (LEFT_MARGIN + width-200)+10, 50);
  controlP5.addTextlabel("0", "0", (LEFT_MARGIN + width-200)+10, 123);
  controlP5.addTextlabel("-1", "-1", (LEFT_MARGIN + width-200)+8, 193);
  

  // loop through to create the pattern-specific bits of the system
  // since for stereo and morphs we need multiples of all of this
  for(int i=0; i < NUM_PATTERNS; i++) {
    // the fractal model
    fract[i] = new FloatFract();

    // bank of vertical pattern sliders that can work as a "draw" area
    patternSliders[i] = new FWSliderPool(round(stepsSlider.value()), MAX_SLIDERS, LEFT_MARGIN, 0, width-200, 0);
    // set initial values for pattern sliders
    float[] vals = { 1, 0.5, 1 };
    for (int j = 0; j < patternSliders[i].size(); j++)
      patternSliders[i].slider(j).setValue(vals[j]);

    // fractal iteration viewer
    fractView[i] = new IterationView(fract[i].getSegments(), 10, 0, 0, width, 0);
    mouseListeners.add(patternSliders[i]);
  }
  
  stereo(1);
}

/**
  * controlP5 event callbacks
  */

public void a(float val) {
  numPatternsActive = 1;
  patternOffset = 0;
  morphing = false;
  setSingleView(0);
}

public void b(float val) {
  numPatternsActive = 1;
  patternOffset = 1;
  morphing = false;
  setSingleView(1);
}

public void stereo(float val) {
  numPatternsActive = 2;
  patternOffset = 0;
  morphing = false;
  setDoubleView();
}

public void morph(float val) {
  numPatternsActive = 2;
  patternOffset = 0;
  morphing = true;
  setDoubleView();
}

public void setSingleView(int num) {
  patternSliders[num].clear();  
  patternSliders[1-num].clear();  

  patternSliders[num].setHeight(160);
  patternSliders[num].setY(50);
  patternSliders[num].show();

  patternSliders[1-num].hide();
  
  fractView[num].setY(height-30);
  fractView[num].setHeight(-230);
  fractView[num].show();

  fractView[1-num].hide();

  playback.waveDirty = true;
  updateFractalSettings();
}

public void setDoubleView() {
  for(int p = 0; p < numPatternsActive; p++) {
    patternSliders[p].clear();
    patternSliders[p].setY(50+(p*(10+150/NUM_PATTERNS)));
    patternSliders[p].setHeight(150/NUM_PATTERNS);
    patternSliders[p].show();

    fractView[p].clear();
    fractView[p].setY(height-150);  
    fractView[p].setHeight((p==0?-1:1)*230/NUM_PATTERNS);
    fractView[p].show();  
  }
  playback.waveDirty = true;
  updateFractalSettings();
}

public void swap(float val) {
  for (int i = 0; i < patternSliders[0].size(); i++) {
    float tempVal = patternSliders[0].slider(i).value();
    patternSliders[0].slider(i).setValue(patternSliders[1].slider(i).value());
    patternSliders[1].slider(i).setValue(tempVal);
  }
  playback.waveDirty = true;
  updateFractalSettings();
}


public void steps(float val) {
  stepsSlider.setValueLabel(""+round(val));
  checkNumSliders();
}

public void duration(float val) {
  // this will get polled in mouseReleased()
}

public void save(float val) {
  doSave();
}


/**
  * applet events
  */

public void stop() {
  Ess.stop();
  super.stop();
}


public void draw() {
  for(int p = 0; p < numPatternsActive; p++)
    patternSliders[p+patternOffset].draw();

  playback.drawPlayhead();
  
  // process any updates
  boolean stillIterating = false;
  for(int p = 0; p < numPatternsActive; p++) {
    int pat = p + patternOffset;
    if(fract[pat].iteration() < targetIteration) {
      fractView[pat].draw();
      fract[pat].iterate();
      fractView[pat].setNextIteration(fract[pat].getSegments());
      stillIterating = true;
    }
  } 
  if (!stillIterating && playback.waveDirty && playback.audioPlaying) {
    playback.stopAudio();
    if (numPatternsActive == 2) {
      playback.writeStereoAudio(fract[0].getSegments(), fract[1].getSegments());      
    } else {
      for(int p = 0; p < numPatternsActive; p++) {
        int pat = p + patternOffset;
        playback.writeAudio(fract[pat].getSegments(), p);
      }
    }
    playback.playAudio();
  }  
}


void mousePressed() {
  for(int i = 0; i < mouseListeners.size(); i++)
    ((MouseListener)mouseListeners.get(i)).mousePressed();  
}

void mouseReleased() {
  for(int i = 0; i < mouseListeners.size(); i++)
    ((MouseListener)mouseListeners.get(i)).mouseReleased();  
  checkNumSliders();
  checkDuration();
  updateFractalSettings();
}



void dropEvent(DropEvent theDropEvent) {
  if(theDropEvent.isFile()) {
    // for further information see
    // http://java.sun.com/j2se/1.4.2/docs/api/java/io/File.html
    File myFile = theDropEvent.file();
    if(myFile.isFile()) {
      // attempt to parse filename
      String fileName = myFile.getName();
      doRestore(fileName);
    }
  }
}


/*
 * Control Functions
 */ 

void doSave() {
  playback.stopAudio();
  String defaultFilename = "";
  
  for(int p = 0; p < numPatternsActive; p++) {
    int pat = p + patternOffset;
    
    defaultFilename = "fw_"+fract[pat].toString();
    if(morphing)
      defaultFilename += "->"+fract[1-pat].toString();
      
    if(defaultFilename.length() > 250) {
      defaultFilename = defaultFilename.substring(0, 250);
    }
    defaultFilename += ".aif";
  
    String path = "" + defaultFilename;
    print("Save path: " + path + "\n");  
    playback.writeSoundFile(path, pat);
  }
  
  playback.playAudio();
}

void doRestore(String fileName) {
  if(fileName.endsWith(".aif") && fileName.startsWith("fw_")) {
    // looks OK-ish
    fileName = fileName.substring(3, fileName.length()-4);  // strip pre- and suffix
    //print("restoring seed:" + fileName);
    playback.stopAudio();
    playback.invalidateAudio();

    FloatFract newFract = new FloatFract(fileName);
    // copy seed onto UI sliders
    stepsSlider.setValue(newFract.pattern().size());
    checkNumSliders();
    checkDuration();
    for(int i = 0; i < patternSliders[patternOffset].size(); i++)
      patternSliders[patternOffset].slider(i).setValue(((Double)newFract.pattern().get(i)).floatValue());
    updateFractalSettings();
    playback.playAudio();
  }
}

void checkNumSliders() {
  for(int p = 0; p < NUM_PATTERNS; p++) {
    if(patternSliders[p].size() != round(stepsSlider.value())) {
      playback.stopAudio();    
      patternSliders[p].setSize((round(stepsSlider.value())));
      Runtime.getRuntime().gc(); 
    }
  }
}  

void checkDuration() {
  if(curDuration != durationSlider.value()) {
    curDuration = durationSlider.value();
    if(targetIteration != calculateIterationBounds(0))
      playback.waveDirty = true;
  }
}


void updateFractalSettings() {
  boolean needsUpdate = false;
  boolean waveWasDirty = playback.waveDirty;
  ArrayList[] newPattern = new ArrayList[numPatternsActive];
  for(int p = 0; p < numPatternsActive; p++) {
    if(!morphing)
      fract[p+patternOffset].setMorphPattern(null);

    newPattern[p] = new ArrayList(patternSliders[p+patternOffset].size());
    for(int i = 0; i < patternSliders[p+patternOffset].size(); i++) {
      newPattern[p].add(new Double(patternSliders[p+patternOffset].slider(i).value()));
    }
    if(waveWasDirty || (!patternsSame(newPattern[p], fract[p+patternOffset].pattern()))) {
      needsUpdate = true;
    }
  }
  
  if(needsUpdate) {
    targetIteration = calculateIterationBounds(0);
    for(int p = 0; p < numPatternsActive; p++) {
      fract[p+patternOffset].setPattern(newPattern[p]); 
      if(morphing) {
        fract[p+patternOffset].setMorphPattern(newPattern[1-p]); 
      }
      fractView[p+patternOffset].reset(this);
      fractView[p+patternOffset].setNextIteration(fract[p+patternOffset].getSegments());
    }
    playback.invalidateAudio();
    Runtime.getRuntime().gc(); 
    playback.playAudio();    
  }
}

int calculateIterationBounds(int p) { 
  // numSliders^iteration = total samples
  float targetLength = durationSlider.value();
  float numIterations = log(SR*targetLength) / log(patternSliders[p].size());
  
  int targetIteration = ceil(numIterations); // favor longer clips
  // unless it would be too long
  if (pow(patternSliders[p].size(), targetIteration) >= SR*targetLength*4)
    targetIteration--;
    
  return targetIteration;
}


