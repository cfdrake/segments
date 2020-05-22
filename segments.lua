-- ~~ segments ~~
--
-- looping audio resequencer
--
-- KEY2 records audio
--      slices will auto-assign to midi keyboard
--
-- KEY3 records slice playback from keyboard
--      automatically looped
--      tap once to clear
--
-- ENC1 controls volume of the loop
--
-- inspired by c&g's segmenti
-- patch for organelle

-----------------------------
-- INCLUDES, ETC.
-----------------------------

local pattern_time = require "pattern_time"

-----------------------------
-- STATE
-----------------------------

local recording_audio = false
local recording_pattern = false
local playing_pattern = false
local rec_end = 0
local rec_start = 0
local last_note = 0
local loop_vol = 1

-----------------------------
-- INIT
-----------------------------

function init()
  setup_softcut()
  setup_midi()
  setup_pattern()
end

function setup_softcut()
  softcut.buffer_clear()
  
  -- Setup voice.
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, loop_vol)
  softcut.position(1, 0)
  softcut.play(1, 1)
  softcut.rate(1, 1)
  softcut.loop(1, 1)
  softcut.loop_start(1, 0)
  softcut.loop_end(1, 16)
  softcut.level_slew_time(1, 0.5)
  softcut.fade_time(1, 0.01)

  -- Setup inputs.
  audio.level_adc_cut(1)
  
  softcut.level_input_cut(1,1,1.0)
  softcut.level_input_cut(2,1,1.0)

  softcut.rec_level(1, 1)
  softcut.pre_level(1, 1)
end

function setup_midi()
  m = midi.connect()
  
  m.event = function(data)
    local d = midi.to_msg(data)

    -- Skip MIDI input if recording audio/pattern.    
    if recording_audio or playing_pattern then
      return
    end
    
    -- Play MIDI note, and add to pattern if recording.
    if d.type == "note_on" then
      note = d.note % 12
      midi_note_on(note)
      last_note = note

      if recording_pattern then
        ev = {}
        ev.midi_event = "note_on"
        ev.midi_note = note
        
        pattern:watch(ev)
      end
    elseif d.type == "note_off" then
      note = d.note % 12
      
      -- Allows "legato" playing.
      if note ~= last_note then
        return
      end
      
      midi_note_off()
      
      if recording_pattern then
        ev = {}
        ev.midi_event = "note_off"
        ev.midi_note = note
        
        pattern:watch(ev)
      end
    end
  end
end

function setup_pattern()
  pattern = pattern_time.new()
  pattern.process = process_pattern_event
end

-----------------------------
-- MIDI/PATTERN HANDLING
-----------------------------

function process_pattern_event(ev)
  if ev.midi_event == "note_on" then
    midi_note_on(ev.midi_note)
  elseif ev.midi_event == "note_off" then
    midi_note_off()
  end
end

function midi_note_on(note)
  notes_in_octave = 12
  rec_time = rec_end - rec_start
  time_per_key = rec_time / notes_in_octave
  
  softcut.loop_start(1, note * time_per_key)
  softcut.loop_end(1, (note + 1) * time_per_key)
  softcut.play(1,1)
  softcut.level(1, 1)
end

function midi_note_off()
  softcut.level(1, 0)
end

-----------------------------
-- INPUT HANDLING
-----------------------------

function key(n,z)
  if n == 2 then
    if z == 1 then
      softcut.buffer_clear()
      softcut.loop_end(1, 24)  -- max 2s per key.
      softcut.position(1, 0)
      softcut.rec_level(1, 1)
      softcut.rec(1, 1)
      rec_start = util.time()
      
      recording_audio = true
    elseif z == 0 then
      rec_end = util.time()
      softcut.loop_end(1, util.time() - rec_start)

      softcut.position(1, 0)
      softcut.rec_level(1, 0)
      softcut.rec(1, 0)
      softcut.play(1, 0)
      
      recording_audio = false
    end
  end
  
  if n == 3 then
    if z == 1 then
      softcut.play(1, 0)
      
      pattern:clear()
      pattern:stop()
      pattern:rec_start()
      
      recording_pattern = true
      playing_pattern = false
    elseif z == 0 then
      pattern:rec_stop()
      pattern:start()
      
      recording_pattern = false
      playing_pattern = pattern.count > 0
    end
  end
  
  redraw()
end

function enc(n, d)
  if n == 1 then
    loop_vol = util.clamp(loop_vol + (d * 0.01), 0, 1)
    softcut.level(1, loop_vol)
  end
end

-----------------------------
-- DRAWING
-----------------------------

function redraw()
  screen.clear()

  draw_audio_info()
  draw_pattern_info()
  
  screen.update()
end

function draw_audio_info()
  screen.move(1, 10)
  screen.level(15)
  screen.text("audio >")
  
  screen.move(1, 20)
  screen.level(5)
  
  if recording_audio then
    screen.text(".. recording!")
  elseif rec_end == 0 then
    screen.text(".. empty, KEY2 to record")
  else
    screen.text(".. " .. (math.floor(100*(rec_end - rec_start))/100) .. " seconds recorded")
    screen.move(1, 30)
    screen.text(".. " .. (math.floor(100*(rec_end - rec_start)/12)/100) .. " seconds per slice")
  end
end

function draw_pattern_info()
  screen.move(1, 50)
  screen.level(15)
  screen.text("pattern >")
  
  screen.move(1, 60)
  screen.level(5)
  
  if recording_pattern then
    screen.text(".. recording!")
  elseif playing_pattern then
    screen.text(".. playing!")
  else
    screen.text(".. empty, KEY3 to record")
  end
end