layout = 10 1E 2C 11 1F 2D 12 20 2E 13 21 2F 14 22 30 15 23 31 16 24 32 17 25 33 18 26 34 19 27 35 1A 28 36 1B 2B 148 1C

global midiPort    := 1
     , midiChannel := 0
     , isSustain   := 0
     , isBends     := 1
     , firstNote   := 40
     , octaveIndex := 0
     , velocity    := 110
     , lowVelocity := 90
     , bendRange   := 2
     , ccNumber    := 1
     , ccValue     := 0
, winmm, devOut, devIn
, anyKey := 0
, pressedKeys := {}
, savedKeys := {}
, savedMidi := {}
, buttonsAmount := 0
, lastVelocity := 0
, guiWindow := "ahk_class AutoHotkeyGUI"

#NoEnv
menu tray, icon, imageres.dll, 206
#MaxHotkeysPerInterval 999
#SingleInstance force
SetBatchLines -1
#KeyHistory 0
ListLines off
OnExit("exit")

gui +LastFound +AlwaysOnTop -SysMenu
WinSet trans, 200
gui font, s11, Segoe UI
gui add, text, vguiText w180 h300
gui add, StatusBar
gui show

winmm := DllCall("LoadLibrary", "Str", "winmm")
DllCall("winmm\midiOutOpen", "UInt*", devOut, "UInt", midiPort, "UPtr", 0, "UPtr", 0, "UInt", 0)
DllCall("winmm\midiInOpen", "UInt*", devIn, "UInt", 0, "UInt", WinExist(), "UInt", 0, "UInt", 0x10000)
DllCall("winmm\midiInStart", "UInt", devIn)
OnMessage(0x3C1, "midiInput"), OnMessage(0x3C2, "midiInput"), OnMessage(0x3C3, "midiInput")

setCC(), updateInfo()

for key, code in StrSplit(layout, " ") {
  press := func("keyPress").bind(key)
  hotkey IfWinActive, % guiWindow
  hotkey % GetKeyName("SC" code), % press
  release := func("keyRelease").bind(key)
  hotkey IfWinActive, % guiWindow
  hotkey % GetKeyName("SC" code) " up", % release
  buttonsAmount++
}

#if WinActive(guiWindow)
       RAlt:: isSustain := !isSustain, updateInfo()
    AppsKey:: isBends := !isBends, updateInfo()
   Space up:: (lastVelocity != lowVelocity) and mute()
          2:: mute()
          3::
          4:: mute(0)
          1:: isBends ? bend(2, 1)  :
       1 up:: isBends ? bend(-2)    :
        Tab:: isBends ? bend(1, 1)  : octaveShift(1)
     Tab up:: isBends ? bend(-1)    :
   CapsLock:: isBends ? bend(-1, 1) : octaveShift(-1)
CapsLock up:: isBends ? bend(1)     :
     LShift:: isBends ? bend(-2, 1) : octaveShift()
  LShift up:: isBends ? bend(2)     :
         BS:: bend(-2, 1, 1.5), mute(), DllCall("Sleep", "UInt", 175), pitch(0)
 ScrollLock:: bendRange := bendRange = 2 ? 12 : 2
       Left:: octaveShift(-1)
      Right:: octaveShift(1)
       Down:: octaveShift()
         F3:: mute(), midiChannel -= midiChannel > 0, updateInfo()
         F4:: mute(), midiChannel += midiChannel < 15, updateInfo()
         F6:: (velocity > 20) and velocity -= 10 - 3 * (velocity = 127), updateInfo()
         F7:: (velocity < 127) and velocity += 10 - 3 * (velocity = 120), updateInfo()
        F11:: firstNote -= firstNote > 21, updateInfo()
        F12:: firstNote += firstNote < 72, updateInfo()
       SC29:: (ccOn) or setCC(128), ccOn := 1
    SC29 up:: ccOn := 0, setCC(-128)
    WheelUp:: setCC(10)
  WheelDown:: setCC(-10)
#if

keyPress(k) {
  critical -1
  if pressedKeys[k]
    return
  pressedKeys[k] := 1
  , isSustain and !anyKey and mute()
  , anyKey++
  , m := keyToMidi(k)
  , savedMidi[m] and playNote(-m)
  , playNote(m)
  , savedKeys[k] := octaveIndex
  , savedMidi[m] := m
  SetTimer guiUpdate, -10
}

keyRelease(k) {
  critical -1
  pressedKeys[k] := 0
  if !(anyKey and savedKeys.HasKey(k))
    return
  anyKey--
  if isSustain
    return
  m := keyToMidi(k, savedKeys[k])
  , playNote(-m)
  , savedKeys.delete(k)
  , savedMidi.delete(m)
  SetTimer guiUpdate, -10
}

mute(noStrum:=1) {
  midiSend(0xB0, 0x7B)
  for m in savedMidi
    playNote(-m), noStrum or playNote(m)
  (noStrum) and (anyKey := 0, savedKeys := {}, savedMidi := {})
  SetTimer guiUpdate, -10
}

bend(semitones, value:=0, ms:=1) {
  critical -1
  static middle
  middle := 0
  , semi := abs(semitones)
  , limit := round(100 / bendRange * semitones)
  , step := limit / (bendRange = semi or bendRange * semi = 12 ? 25 : 20)
  , value and value := limit
  if step > 0
    while !middle and pitch() < value
      pitch(step), DllCall("Sleep", "UInt", 2 * ms)
  else
    while !middle and pitch() > value
      pitch(step), DllCall("Sleep", "UInt", 2 * ms)
  (value) or (pitch(0), middle := 1)
}

pitch(value:="") {
  static savedPitch := 0
  if value is number
    savedPitch := !value ? 0 : savedPitch + value
    , savedPitch := savedPitch < -100 ? -100 : savedPitch > 100 ? 100 : savedPitch
    , newPitch -= (newPitch := (100 + savedPitch) / 200 * 0x4000) = 0x4000
    , midiSend(0xE0, newPitch & 0x7F, (newPitch >> 7) & 0x7F)
  return savedPitch
}

playNote(midi) {
  lastVelocity := !isBends or !GetKeyState("Space","P") ? velocity : lowVelocity
  , midiSend(0x90, abs(midi), (midi > 0) * lastVelocity)
}

setCC(value:=0) {
  ccValue += value, ccValue := ccValue < 0 ? 0 : ccValue > 127 ? 127 : ccValue
  , midiSend(0xB0, ccNumber, ccValue)
}

midiSend(command, data1, data2:=0) {
  if WinActive(guiWindow)
    DllCall("winmm\midiOutShortMsg", "UInt", devOut, "UInt", command + midiChannel | data1 << 8 | data2 << 16)
}

midiInput(hInput, midiMsg, wMsg) {
  if WinActive(guiWindow)
    return
  status := midiMsg & 0xF0
  , data1 := (midiMsg >> 8) & 0xFF
  , data2 := (midiMsg >> 16) & 0xFF
  if status between 128 and 159
    key := 1 - (firstNote - data1) - 12 * octaveIndex, data2 and status = 0x90 ? keyPress(key) : keyRelease(key)
  else if (status = 0xB0 and data1 = 0x7B)
    mute()
}

octaveShift(value:=0) {
  octaveIndex += value > 0 ? octaveIndex < 3 : value < 0 ? -(octaveIndex > -2) : octaveIndex := 0
  updateInfo()
}

keyToMidi(key, octave:=7) {
  return firstNote - 1 + key + 12 * (octave = 7 ? octaveIndex : octave)
}

noteName(midi, withOctave:=1) {
  static b := chr(0x266D), # := chr(0x266F), notes := ["C","C"#,"D","E"b,"E","F","F"#,"G","A"b,"A","B"b,"B"]
  return notes[mod(midi, 12) + 1] (withOctave ? midi // 12 - 1 : "")
}

guiUpdate() {
  static degrees := ["n1","b2","n2","b3","n3","n4","b5","n5","b6","n6","b7","n7"]
  , b := chr(0x266D), # := chr(0x266F), hd := chr(0xF8), d := chr(0x2070)
  loop % buttonsAmount
    rowNumber := mod(A_Index - 1, 3), row%rowNumber% .= chr(0x26AA + savedKeys.HasKey(A_Index))
  for i, midi in savedMidi, codes := [], redundantCodes := {} {
    for j, nextMidi in savedMidi
      (j > i) and mod(nextMidi, 12) = mod(midi, 12) and redundantCodes[nextMidi] := 1
    (redundantCodes[midi]) or codes.push(midi)
  }
  chordLength := codes.count()
  loop % chordLength {
    for _, midi in codes
      deg := degrees[mod(abs(midi - codes.1), 12) + 1], %deg% := 1
    mi3     := b3 and !n3
    , ma3   := !b3 and n3
    , no3   := !b3 and !n3 and n5
    , aug   := ma3 and b6 and !n5
    , dim   := mi3 and b5 and !n5
    , dim7  := dim and n6
    , hdim  := dim and !n6 and b7
    , sus2  := no3 and n2 and !n4
    , sus4  := no3 and !n2 and n4
    , is6   := !dim and n6
    , is7   := !dim and (b7 or n7)
    , is9   := !sus2 and n2
    , is11  := !sus4 and n4
    , b9    := b2 ? "(" b "9)" : ""
    , n9    := !is7 and is9 ? "(9)" : ""
    , s9    := b3 and n3 ? "(" # "9)" : ""
    , n11   := !is7 and is11 ? "(11)" : ""
    , s11   := !dim and b5 ? "(" (n5 ? # 11 : b 5) ")" : ""
    , b13   := !aug and b6 ? "(" (n5 ? b 13 : # 5) ")" : ""
    , root  := noteName(codes.1, 0)
    , type  := no3 and chordLength = 2 ? 5 : aug ? "+" : hdim ? hd : dim7 ? d 7 : dim ? d : mi3 ? "m" : ""
    , six   := !is7 and is6 ? 6 : ""
    , maj   := is7 and !b7 ? "maj" : ""
    , dom   := is7 ? is6 ? 13 : is11 ? 11 : is9 ? 9 : 7 : ""
    , sus   := sus2 ? "sus2" : sus4 ? "sus4" : ""
    , add   := " " StrReplace(b9 n9 s9 n11 s11 b13, ")(", ", ")
    , chord .= "`n" root type six maj dom sus add
    for _, deg in degrees
      %deg% := 0
    transposedNote := codes.RemoveAt(1)
    while transposedNote <= codes[chordLength - 1]
      transposedNote += 12
    codes.push(transposedNote)
  }
  GuiControl,, guiText, % row0 "`n " row1 "`n   " row2 chord
}

updateInfo() {
  WinSetTitle % noteName(firstNote) " (" octaveIndex + 2 "-" octaveIndex + 5 "), vel " velocity ", ch " midiChannel + 1
  SB_SetParts(100, 100)
  SB_SetText("sustain " (isSustain ? "ON" : "OFF"))
  SB_SetText("bends " (isBends ? "ON" : "OFF"), 2)
}

guiClose() {
  ExitApp
}

exit() {
  OnMessage(0x3C1, ""), OnMessage(0x3C2, ""), OnMessage(0x3C3, "")
  DllCall("winmm\midiInStop", "UInt", devIn)
  DllCall("winmm\midiInClose", "UInt", devIn)
  DllCall("winmm\midiOutReset", "UInt", devOut)
  DllCall("winmm\midiOutClose", "UInt", devOut)
  DllCall("FreeLibrary", "UPtr", winmm)
  ExitApp
}