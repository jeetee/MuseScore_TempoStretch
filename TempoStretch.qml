//=============================================================================
//  TempoStretch Plugin
//
//  Apply a % change to (selected) tempo markers
//
//  Copyright (C) 2020 Johan Temmerman (jeetee)
//=============================================================================
import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Controls.Styles 1.3
import QtQuick.Layouts 1.1
import QtQuick.Window 2.2
import Qt.labs.settings 1.0

import MuseScore 3.0

MuseScore {
      menuPath: 'Plugins.TempoStretch'
      title: 'TempoStretch'
      version: '4.0.0'
      description: qsTr("Apply a % change to (selected) tempo markers")
      thumbnailName: 'TempoStretch.png'
      categoryCode: 'tools'
      pluginType: 'dialog'
      requiresScore: true
      id: 'pluginId'

      property int startBPMvalue: 120 // Always as 1/4th == this value
      property int beatBaseIndex: 5
      property var beatBaseList: [
            //mult is a tempo-multiplier compared to a crotchet      
            //{ text: '\uECA0'              , mult: 8     , sym: '<sym>metNoteDoubleWhole</sym>' } // 2/1
             { text: '\uECA2'              , mult: 4     , sym: '<sym>metNoteWhole</sym>' } // 1/1
            //,{ text: '\uECA3\uECB7\uECB7' , mult: 3.5   , sym: '<sym>metNoteHalfUp</sym><sym>metAugmentationDot</sym><sym>metAugmentationDot</sym>' } // 1/2..
            ,{ text: '\uECA3\uECB7'        , mult: 3     , sym: '<sym>metNoteHalfUp</sym><sym>metAugmentationDot</sym>' } // 1/2.
            ,{ text: '\uECA3'              , mult: 2     , sym: '<sym>metNoteHalfUp</sym>' } // 1/2
            ,{ text: '\uECA5\uECB7\uECB7'  , mult: 1.75  , sym: '<sym>metNoteQuarterUp</sym><sym>metAugmentationDot</sym><sym>metAugmentationDot</sym>' } // 1/4..
            ,{ text: '\uECA5\uECB7'        , mult: 1.5   , sym: '<sym>metNoteQuarterUp</sym><sym>metAugmentationDot</sym>' } // 1/4.
            ,{ text: '\uECA5'              , mult: 1     , sym: '<sym>metNoteQuarterUp</sym>' } // 1/4
            ,{ text: '\uECA7\uECB7\uECB7'  , mult: 0.875 , sym: '<sym>metNote8thUp</sym><sym>metAugmentationDot</sym><sym>metAugmentationDot</sym>' } // 1/8..
            ,{ text: '\uECA7\uECB7'        , mult: 0.75  , sym: '<sym>metNote8thUp</sym><sym>metAugmentationDot</sym>' } // 1/8.
            ,{ text: '\uECA7'              , mult: 0.5   , sym: '<sym>metNote8thUp</sym>' } // 1/8
            ,{ text: '\uECA9\uECB7\uECB7'  , mult: 0.4375, sym: '<sym>metNote16thUp</sym><sym>metAugmentationDot</sym><sym>metAugmentationDot</sym>' } //1/16..
            ,{ text: '\uECA9\uECB7'        , mult: 0.375 , sym: '<sym>metNote16thUp</sym><sym>metAugmentationDot</sym>' } //1/16.
            ,{ text: '\uECA9'              , mult: 0.25  , sym: '<sym>metNote16thUp</sym>' } //1/16
      ]

      width:  240
      height: 160

      onRun: {
            findStartBPM();
            // Now show it
            var beatBaseItem = beatBaseList[beatBaseIndex];
            startTempoTxt.text = beatBaseItem.text.split('').join(' ') + ' = ' + (Math.round(startBPMvalue / beatBaseItem.mult * 10) / 10);
            // Force dependency calculation
            percentValue.text = '100';
      }

      function findStartBPM()
      {
            var segment = getSelection();
            if (segment === null) {
                  //segment = curScore.firstSegment(ChordRest); // only read firstSegment available here
                  // Rather than forwarding to find the first ChordRest, we can use Cursor instead
                  //  which filters on ChordRests by default
                  segment = curScore.newCursor();
                  segment.rewind(Cursor.SCORE_START);
                  segment = segment.segment;
            }
            else {
                  segment = segment.startSeg;
            }
            // Start Tempo
            var foundTempo = undefined;
            while ((foundTempo === undefined) && (segment)) {
                  foundTempo = findExistingTempoElement(segment);
                  segment = segment.prev;
            }
            if (foundTempo !== undefined) {
                  console.log('Found start tempo text = ' + foundTempo.text);
                  // Try to extract base beat
                  beatBaseIndex = analyseTempoMarking(foundTempo).beatBase.index;
                  if (beatBaseIndex == -1) {
                        // Couldn't identify it from the text, default to 1/4th note
                        beatBaseIndex = 5;
                  }
                  startBPMvalue = Math.round(foundTempo.tempo * 60 * 10) / 10;;
            }
            else { // No tempo marking found, add one ourselves
                  curScore.startCmd();
                  var newTempo = newElement(Element.TEMPO_TEXT);
                  newTempo.text = beatBaseList[5].text.split('').join(' ') + ' = ' + startBPMvalue;
                  newTempo.followText = true;
                  newTempo.visible = false;
                  var cursor = curScore.newCursor();
                  cursor.rewind(Cursor.SCORE_START);
                  cursor.add(newTempo);
                  newTempo.tempo = startBPMvalue / 60; // Changing tempo is only possible after being added to the score
                  curScore.endCmd(false);
            }
      }

      /// Analyses tempo marking text
      /// Split tempo marking into 5 substrings with additional analysis:
      ///      {startOfString, beatBase{string, index}, middleStringEquals, valueString, endOfString}
      ///      isMetricModulation
      ///      isValidBasic
      /// A valid basic marking will contain non-empty strings for beatBaseIndex, middleStringEquals and valueString
      function analyseTempoMarking(tempoMarking)
      {
            var tempoInfo = {
                  startOfString: '',
                  beatBase: { string: '', index: -1 },
                  middleStringEquals: '',
                  valueString: '',
                  endOfString: '',
                  isValidBasic: false,
                  isMetricModulation: false
            };
            var tempoString = tempoMarking.text;
            // Look for metronome marking symbols (<sym>met.*<\/sym>)
            // Metronome marking symbols are substituted with their character entity if the text was edited
            // UTF-16 range [\uECA0 - \uECB6] (double whole - 1024th)
            var foundMetronomeSymbols = tempoString.match(/(<sym>met.*<\/sym>((<sym>space<\/sym>)?<sym>met.*<\/sym>)*)|([\uECA2-\uECB7]( ?[\uECA2-\uECB7])*)/);
            if (foundMetronomeSymbols !== null) {
                  // Everything before the marking
                  tempoInfo.startOfString = tempoString.slice(0, foundMetronomeSymbols.index);
                  // beatBase
                  tempoInfo.beatBase.string = foundMetronomeSymbols[0];
                  tempoString = tempoString.slice(foundMetronomeSymbols.index + foundMetronomeSymbols[0].length);
                  if (foundMetronomeSymbols[0][0] == '<') { // xml marking
                        foundMetronomeSymbols[0] = foundMetronomeSymbols[0].replace('<sym>space</sym>', ''); // Stripped those to match beatBaseList.sym
                  }
                  else { // plain text marking
                        foundMetronomeSymbols[0] = foundMetronomeSymbols[0].replace(' ', ''); // Stripped those to match beatBaseList.text
                  }
                  for (tempoInfo.beatBase.index = beatBaseList.length; --tempoInfo.beatBase.index >= 0; ) {
                        var beatBaseItem = beatBaseList[tempoInfo.beatBase.index];
                        if (   (beatBaseItem.sym  == foundMetronomeSymbols[0])
                            || (beatBaseItem.text == foundMetronomeSymbols[0])
                            ) {
                              break; // Found this marking in the dropdown at current index
                        }
                  }
                  // Continue with remainder, now without beat marking
                  tempoInfo.middleStringEquals = tempoString.match(/(<.*>)*[^=]*=\s+/);
                  tempoInfo.middleStringEquals = (tempoInfo.middleStringEquals !== null)? tempoInfo.middleStringEquals[0] : '';
                  tempoString = tempoString.slice(tempoInfo.middleStringEquals.length);
                  // Extract value, assume it is a number
                  var foundValue = tempoString.match(/^(\d+(\.\d+)?)/);
                  if (foundValue !== null) {
                        tempoInfo.valueString = foundValue[0];
                        tempoInfo.endOfString = tempoString.slice(tempoInfo.valueString.length);
                        tempoInfo.isValidBasic = (tempoInfo.beatBaseIndex !== -1) && (tempoInfo.middleStringEquals.length > 0);
                  }
                  else { // No number, perhaps a metronome marking?
                        foundMetronomeSymbols = tempoString.match(/((<sym>met.*<\/sym>((<sym>space<\/sym>)?<sym>met.*<\/sym>)*)|([\uECA2-\uECB7]( ?[\uECA2-\uECB7])*))/);
                        if (foundMetronomeSymbols !== null) {
                              // There might be some markup in front of a 2nd marking, include it in the middle part
                              tempoInfo.middleStringEquals += tempoString.slice(0, foundMetronomeSymbols.index);
                              tempoInfo.valueString = foundMetronomeSymbols[0];
                              tempoInfo.endOfString = tempoString.slice(foundMetronomeSymbols.index + tempoInfo.valueString.length);
                              tempoInfo.isMetricModulation = true;
                        }
                  }
            }
            else {
                  // Couldn't find a single metronome mark
                  tempoInfo.startOfString = tempoString;
            }
            return tempoInfo;
      }

      function applyTempoStretch()
      {
            var sel = getSelection();
            if (sel === null) { //no selection
                  console.log('No selection - using full score');
                  sel = {
                        startSeg: curScore.firstSegment(),
                        endSeg:   curScore.lastSegment
                  }
            }

            curScore.startCmd();
            // Scan through all relevant segments
            var segment = sel.startSeg;
            do {
                  if (segment.segmentType == Segment.ChordRest) {
                        var foundTempoMarking = findExistingTempoElement(segment);
                        if (foundTempoMarking !== undefined) {
                              // Found a tempo marking; analyse it
                              var tempoInfo = analyseTempoMarking(foundTempoMarking);
                              if (!tempoInfo.isMetricModulation) { // metric modulation can be ignored, will auto-scale
                                    var newTempo = foundTempoMarking.tempo * percentSlider.value / 100;
                                    foundTempoMarking.tempo = newTempo;
                                    if (tempoInfo.isValidBasic) {
                                          // text should be updated
                                          newTempo = newTempo * 60 / beatBaseList[tempoInfo.beatBase.index].mult;
                                          foundTempoMarking.text = tempoInfo.startOfString
                                                                 + tempoInfo.beatBase.string
                                                                 + tempoInfo.middleStringEquals
                                                                 + (Math.round(newTempo * 10) / 10)
                                                                 + tempoInfo.endOfString;
                                    }
                              }
                        }
                  }
            } while ((segment.tick != sel.endSeg.tick) && (segment = segment.next));

            curScore.endCmd(false);
      }

      function getSelection()
      {
            var selection = null;
            var cursor = curScore.newCursor();
            cursor.rewind(Cursor.SELECTION_START); //start of selection
            if (!cursor.segment) { //no selection
                  console.log('No selection');
                  return selection;
            }
            selection = {
                  start: cursor.tick,
                  startSeg: cursor.segment,
                  end: null,
                  endSeg: null
            };
            cursor.rewind(Cursor.SELECTION_END); //find end of selection
            if (cursor.tick == 0) {
                  // this happens when the selection includes
                  // the last measure of the score.
                  // rewind(2) goes behind the last segment (where
                  // there's none) and sets tick=0
                  selection.end = curScore.lastSegment.tick + 1;
                  selection.endSeg = curScore.lastSegment;
            }
            else {
                  selection.end = cursor.tick;
                  selection.endSeg = cursor.segment;
            }
            return selection;
      }

      function getFloatFromInput(input)
      {
            var value = input.text;
            if (value == "") {
                  value = input.placeholderText;
            }
            return parseFloat(value);
      }

      function findExistingTempoElement(segment)
      { //look in reverse order, there might be multiple TEMPO_TEXTs attached
            // in that case MuseScore uses the last one in the list
            if (segment && segment.annotations) {
                  for (var i = segment.annotations.length; i-- > 0; ) {
                        if (segment.annotations[i].type === Element.TEMPO_TEXT) {
                              return (segment.annotations[i]);
                        }
                  }
            }
            return undefined; //invalid - no tempo text found
      }


      ColumnLayout {
            id: 'mainLayout'
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 0
            anchors.bottomMargin: 10

            focus: true

            GridLayout {
                  columns: 2
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  anchors.topMargin: 5
                  anchors.bottomMargin: 5
                                    
                  Label {
                        text: qsTr("From:")
                        Layout.alignment: Qt.AlignRight
                  }
                  Label {
                        id: startTempoTxt
                        Layout.fillWidth: true
                        bottomPadding: -10
                        font.pointSize: 9
                  }

                  Label {
                        text: qsTr("To:")
                        Layout.alignment: Qt.AlignRight
                  }
                  TextField {
                        id: toBPMvalue
                        placeholderText: '60'
                        validator: DoubleValidator { bottom: 0.1;/* top: 512;*/ decimals: 1; notation: DoubleValidator.StandardNotation; }
                        implicitHeight: 24
                        onTextChanged: {
                              percentValue.text = Math.round((getFloatFromInput(toBPMvalue) * beatBaseList[beatBaseIndex].mult * 100 / startBPMvalue) * 10) / 10;
                        }
                  }
            }

            RowLayout {
                  Slider {
                        id: percentSlider
                        Layout.fillWidth: true

                        minimumValue: 1
                        maximumValue: 400
                        value: 100.0
                        stepSize: 0.1

                        onValueChanged: {
                              percentValue.text = Math.round(value * 10) / 10;
                        }

                  }
                  TextField {
                        id: percentValue
                        text: '10'
                        validator: DoubleValidator { bottom: 0.1;/* top: 512;*/ decimals: 1; notation: DoubleValidator.StandardNotation; }
                        Layout.alignment: Qt.AlignRight
                        Layout.preferredWidth: 50
                        implicitHeight: 24
                        onTextChanged: {
                              var newValue = getFloatFromInput(percentValue);
                              if (newValue > percentSlider.maximumValue) {
                                    percentSlider.maximumValue = newValue; // Increase range
                              }
                              percentSlider.value = newValue;
                              // Update BPM field
                              if (toBPMvalue.text == '') {
                                    toBPMvalue.placeholderText = Math.round((startBPMvalue * newValue / 100) * 10) / 10;
                              }
                              else {
                                    toBPMvalue.text = Math.round((startBPMvalue * newValue / 100) * 10) / 10;
                              }
                        }
                  }
                  Label { text: '%' }
            }

            Button {
                  id: applyButton
                  Layout.alignment: Qt.AlignRight
                  text: qsTranslate("PrefsDialogBase", "Apply")
                  onClicked: {
                        applyTempoStretch();
                        pluginId.parent.Window.window.close();
                  }
            }
      }

      Keys.onEscapePressed: {
            pluginId.parent.Window.window.close();
      }
      Keys.onReturnPressed: {
            applyTempoStretch();
            pluginId.parent.Window.window.close();
      }
      Keys.onEnterPressed: {
            applyTempoStretch();
            pluginId.parent.Window.window.close();
      }
}
