-- ~~ segments ~~
--
-- slicing audio looper
--
-- KEY2 hold to record audio
--      assigns slices to midi keyboard
--
-- KEY3 hold to record slice playback
--      loops on release
--      tap again to clear
--
-- ENC1 slice volume
-- ENC2 slice octave
-- ENC3 slice direction
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
local MAX_RECORD_TIME = 24

local loop_vol = 1
local loop_direction = 1
local loop_octave = 1

local AMP_POLL_TIME = 0.2
local amp_samples_l = {}

-----------------------------
-- INIT
-----------------------------

function init()
  setup_softcut()
  setup_midi()
  setup_pattern()
  setup_polls()
end

function setup_polls()
  amp_in_left_poll = poll.set('amp_in_l')
  amp_in_left_poll.callback = function(x)
    recording_time = util.time() - rec_start
    
    if recording_audio and recording_time < MAX_RECORD_TIME then
      table.insert(amp_samples_l, x)
      redraw()
    end
  end
  
  amp_in_left_poll.time = AMP_POLL_TIME
  amp_in_left_poll:start()
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
  softcut.level(1, loop_vol)
  
  redraw()
end

function midi_note_off()
  softcut.level(1, 0)
  
  redraw()
end

-----------------------------
-- INPUT HANDLING
-----------------------------

function key(n,z)
  if n == 2 then
    -- Audio recorder.
    if z == 1 then
      pattern:clear()
      pattern:stop()
      
      recording_pattern = false
      playing_pattern = false

      softcut.buffer_clear()
      
      softcut.rate(1, 1)
      softcut.loop_start(1, 0)
      softcut.loop_end(1, MAX_RECORD_TIME)
      softcut.loop(1, 0)
      softcut.position(1, 0)
      softcut.rec_offset(1, 0)
      softcut.rec_level(1, 1)
      softcut.rec(1, 1)
      softcut.play(1, 0)
      rec_start = util.time()
      
      amp_samples_l = {}
      recording_audio = true
    elseif z == 0 then
      softcut.rate(1, loop_direction * loop_octave)
      
      rec_end = util.time()
      softcut.loop_end(1, util.time() - rec_start)

      softcut.loop(1, 1)
      softcut.position(1, 0)
      softcut.rec_level(1, 0)
      softcut.rec(1, 0)
      softcut.play(1, 0)
      
      recording_audio = false
      
      print("Recorded " .. (rec_end - rec_start) .. " seconds of audio...")
    end
  end
  
  if n == 3 then
    -- Pattern recorder.
    if z == 1 then
      if playing_pattern then
        softcut.play(1, 0)
      end
      
      pattern:clear()
      pattern:stop()
      pattern:rec_start()
      
      recording_pattern = true
      playing_pattern = false
    elseif z == 0 then
      midi_note_off()
      
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
    -- Set loop volume.
    loop_vol = util.clamp(loop_vol + (d * 0.01), 0, 1)
    softcut.level(1, loop_vol)
  elseif n == 2 then
    -- Set loop octave.
    if d > 0 then
      loop_octave = 1
    else
      loop_octave = 0.5
    end
    
    softcut.rate(1, loop_direction * loop_octave)
  elseif n == 3 then
    -- Set loop direction.
    if d < 0 then
      loop_direction = -1
    else
      loop_direction = 1
    end
    
    softcut.rate(1, loop_direction * loop_octave)
  end
  
  redraw()
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
  
  screen.move(80, 10)
  screen.level(15)
  screen.text("o: ")
  screen.level(5)
  screen.text(loop_octave == 1 and "+" or "-")
  
  screen.move(99, 10)
  screen.level(15)
  screen.text("d: ")
  screen.level(5)
  screen.text(loop_direction == 1 and "fwd" or "rev")
  
  if rec_start == 0 and rec_end == 0 and not recording_audio then
    screen.move(1, 20)
    screen.level(1)
    screen.text(".. empty, hold KEY2 to record")
  else
    screen.level(5)
    
    if #amp_samples_l > 0 then
      max_amp_l = math.max(table.unpack(amp_samples_l))
      
      for i=1,#amp_samples_l do
        amp_l = (amp_samples_l[i] / max_amp_l) * 10
        
        screen.move(i, 20)
        screen.rect(i, 25, 1, -amp_l)
        screen.fill()
        screen.rect(i, 25, 1, amp_l)
        screen.fill()
      end
    end
  end
end

function draw_pattern_info()
  screen.move(1, 50)
  screen.level(15)
  screen.text("pattern >")
  
  screen.move(1, 60)
  screen.level(5)
  
  if recording_pattern then
    screen.level(5)
    screen.text(".. recording!")
  elseif playing_pattern and (rec_start ~= 0 and rec_end ~=0) then
    screen.level(5)
    screen.text(".. playing! tap KEY3 to cancel")
  else
    screen.level(1)
    screen.text(".. empty, hold KEY3 to record")
  end
end