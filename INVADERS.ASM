; ============================================================================
; STAR SIEGE v0.7 - adaptive soundtrack - TRS-80 Model III / Yamaha EMT-10
; Original recreation inspired by Space Intruders (1980), not a port of its code.
; Original Space Invaders-style game. MIT licence - see LICENSE.
; ============================================================================
; TARGET AND ASSUMPTIONS
;   48K Model III, LDOS 5.3.1, 64 columns x 16 rows, Z80.
;   Select the actual LDOS timer frequency (25 or 30 Hz) at the menu.
;   LDOS interrupts must remain active to update TIMER$. No DI/EI or custom ISR.
;   Model I and TRSDOS compatibility have not been established.
;   MIDI is optional: external 9600 8N1 RS-232-to-31250 MIDI bridge required.
;   Cassette effects and MIDI output are separate physical audio paths.
;
; HARDWARE INTERFACE (addresses in hexadecimal)
;   3800-38FF  memory-mapped keyboard matrix (active-high key bits).
;   3810       bits 2..5 = '2'..'5' (clock and audio transport).
;   3840       bit 0 ENTER, 1 CLEAR, 2 BREAK, 5 LEFT, 6 RIGHT, 7 SPACE.
;   3C00-3FFF  1024-byte video RAM, one byte per character cell.
;   402D       LDOS return-to-DOS entry used at exit.
;   4288       low byte of LDOS TIMER$ (wraps from FF to 00).
;   E8/E9/EA   serial board configuration; EA read bit 6 = TX ready.
;   EB         UART transmit data register; write raw binary MIDI bytes.
;   FF         cassette output; effects alternate values 1 and 0.
;
; MEMORY LAYOUT
;   See generated INVADERS.MAP for exact addresses; origin 6000H.
;   35 alien flags, two shield rows, 1K back buffer, 128-byte private stack.
;   MIDI uses a small foreground queue; DOS memory is not overwritten.
;   New sprite data is original; 6x3 pixel masks packed into TRS-80 blocks.

; CONTROL FLOW
;   start -> menu -> optional title_intro -> begin -> newwave -> frame_wait.
;   menu -> demo_start -> begin -> same frame loop -> demo_end -> menu.
;   Demo is silent; synthetic key bits reuse the player routine.
;   Each observed timer change: player, shot, aliens, bomb, render/collisions,
;   cassette effect, music scheduler, UART pump, game-over/wave checks.
;   gameover -> again -> menu; BREAK -> quit -> LDOS.
;   Game ticks are sampled; music separately consumes elapsed LDOS ticks.
;   No DOS disk I/O during play. Screen and audio share the foreground CPU.
;
; CALLING CONVENTION
;   No general callee-save convention: assume AF/BC/DE/HL are volatile unless
;   explicitly stated. The code uses memory variables across routine calls.
;   Comments specify local contracts, flags and important side effects.
;   Tail JP to a routine ending in RET reuses the caller's return address.
;   Generated music tables must stay between the two exact marker comments;
;   make_intro.py and embed_intro.py regenerate them, build.py assembles CMD.
; ============================================================================
org 0x6000

; ==========================================================================
; 01 / ENTRY, MENU AND IDLE TIMER
; ==========================================================================
; Save the caller stack, switch to private stack, clear MIDI enable and
; force cassette output low. No arguments from LDOS are consumed.
start:
    ld (savedsp),sp
    ld sp,stacktop
    xor a
    ld (midi),a
    ld (buffered),a
    out (0xff),a
    ld a,5                   ; Default 25 Hz until user chooses clock.
    ld (musicrate),a

; Clear the off-screen buffer and write zero-terminated menu strings at
; fixed offsets (row*64+column), then copy the whole buffer to video RAM.
menu:
    xor a
    ld (demo),a
    ld (midi),a
    ld (streaming),a
    call blank
    ld hl,pointsmsg
    ld de,screen+80
    call text
    ld hl,title
    ld de,screen+210
    call text
    ld hl,help1
    ld de,screen+330
    call text
    ld hl,help2
    ld de,screen+457
    call text
    ld hl,help3
    ld de,screen+585
    call text
    ld hl,help4
    ld de,screen+714
    call text
    ld hl,demomsg
    ld de,screen+840
    call text
    call present
    call show_audio_mode
    call menu_timer_reset

; 2/3 select raw 25/30 Hz; 4/5 select buffered 25/30 Hz.
; The latter require MIDIPLAY v0.8/v0.9 compatible Nano firmware.
; Clock and transport remain selected until changed; default is raw 25 Hz.
menu_wait:
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    ld a,(0x3810)
    ld c,0
    bit 2,a
    jp nz,clock25
    bit 3,a
    jp nz,clock30
    ld c,1
    bit 4,a
    jp nz,clock25
    bit 5,a
    jp z,menu_actions
clock30:
    ld b,6
    jp clock_set
clock25:
    ld b,5
clock_set:
    ld a,(musicrate)
    cp b
    jp nz,clock_changed
    ld a,(buffered)
    cp c
    jp z,menu_actions
clock_changed:
    ld a,b
    ld (musicrate),a
    ld a,c
    ld (buffered),a
    call show_audio_mode
    call menu_timer_reset
menu_actions:
    ld a,(0x3840)
    bit 7,a
    jp nz,demo_start
    bit 1,a
    jp nz,begin
    bit 0,a
    jp nz,menu_music
menu_idle:
    ; Six seconds of inactivity (150 or 180 ticks, both below wrap).
    ld a,(musicrate)
    cp 5
    ld b,150
    jp z,menu_limit
    ld b,180
menu_limit:
    ld a,(menutick)
    ld c,a
    ld a,(0x4288)
    sub c
    cp b
    jp nc,demo_start
    jp menu_wait
show_audio_mode:
    ; All four strings have identical lengths; overwrite the old status.
    ld hl,raw25msg
    ld a,(buffered)
    or a
    jp z,show_clock
    ld hl,buf25msg
show_clock:
    ld a,(musicrate)
    cp 5
    jp z,show_mode_text
    ld de,20
    add hl,de
show_mode_text:
    ld de,0x3c00+970
    jp text

menu_timer_reset:
    ld a,(0x4288)
    ld (menutick),a
    ret
menu_music:
    ld a,1
    ld (midi),a
    xor a
    out (0xe8),a
    ld a,0xee
    out (0xe9),a
    ld a,0x6f
    out (0xea),a
    call title_intro

; ==========================================================================
; 02 / START A NEW GAME (ALSO USED BY ATTRACT MODE)
; ==========================================================================
; Reset score to four ASCII zero digits, three lives and wave 1.
; Reset the software MIDI queue and melody state. If MIDI is enabled,
; queue the 14-byte gameplay setup (pedals off, all notes off, program 71).
; Jump to newwave; later waves bypass this score/lives reset.
begin:
    ld hl,score
    ld b,4
    ld a,48
score_reset:
    ld (hl),a
    inc hl
    djnz score_reset
    ld a,3
    ld (lives),a
    ld a,1
    ld (wave),a
    xor a
    ld (qcount),a
    ld (qpos),a
    ld (musicindex),a
    ld (musiclive),a
    ld (streaming),a
    ld (oldbass),a
    ld (oldupper),a
    ld a,1
    ld (musicwait),a
    ld a,(midi)
    or a
    jp z,newwave
    ld a,(0x4288)
    ld (musicclock),a
    ld de,queue
    ld a,(buffered)
    or a
    jp z,game_music_setup
    ld (streaming),a
    ld a,(musicrate)
    cp 5
    ld a,253                  ; FD: timed start at 25 Hz.
    jp z,game_start_token
    ld a,249                  ; F9: timed start at 30 Hz.
game_start_token:
    ld (queue),a
    inc de
game_music_setup:
    ld hl,setup_midi
    ld bc,14
    ldir
    ld a,(streaming)
    add a,14
    ld (qcount),a
    jp newwave

; =====================================================================
; ATTRACT MODE: reuse normal game rules; only input and audio differ.
; SPACE starts manually, idle timer also starts it. Release the triggering
; key before accepting a cancellation. No score can change the high score.
; A deterministic AI patrols gaps between bunkers and fires on arrival.
; 500/600 observed updates (~20 seconds, longer if frames are missed).
; =====================================================================
demo_start:
    ld a,1
    ld (demo),a
    ld (demogate),a
    xor a
    ld (midi),a
    ld (demoindex),a
    ld hl,500
    ld a,(musicrate)
    cp 5
    jp z,demo_duration
    ld hl,600
demo_duration:
    ld (demoticks),hl
    jp begin

; Input A from keyboard matrix. Return NZ on a cancellation; Z otherwise.
; Gate stops the SPACE key that launched the demo also cancelling it.
demo_cancel:
    and 227                    ; ENTER, CLEAR, LEFT, RIGHT, SPACE
    ld b,a
    ld a,(demogate)
    or a
    jp z,demo_cancel_ready
    ld a,b
    or a
    jp nz,demo_cancel_ignore
    ld (demogate),a
demo_cancel_ignore:
    xor a
    ret
demo_cancel_ready:
    ld a,b
    or a
    ret

; Leave attract mode without a game-over screen. Wait for cancellation
; keys to be released, then redraw menu. BREAK works even while held.
demo_end:
    xor a
    ld (demo),a
    ld (midi),a
    out (0xff),a
demo_release:
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    and 227
    jp nz,demo_release
    jp menu

; Return synthetic keyboard bits in A. Aim at four unobstructed lanes.
; At a target stay until the laser has completed, then advance the lane.
; The existing player routine provides movement, fire latch and collision.
demo_keys:
    ld a,(demoindex)
    and 3
    ld e,a
    ld d,0
    ld hl,demo_lanes
    add hl,de
    ld b,(hl)
    ld a,(px)
    cp b
    jp c,demo_right
    jp nz,demo_left
    ld a,(shoty)
    or a
    jp nz,demo_no_key
    ld a,(fireheld)
    or a
    jp nz,demo_no_key
    ld a,(demoindex)
    inc a
    ld (demoindex),a
    ld a,128
    ret
demo_no_key:
    xor a
    ret
demo_right:
    ld a,64
    ret
demo_left:
    ld a,32
    ret
; Title music uses absolute LDOS tick deadlines. No disk reads or busy waits
; on the UART; each record is (tick, byte count, full MIDI messages).

; ==========================================================================
; 03 / EMBEDDED TITLE MUSIC
; ==========================================================================
; Entry: MIDI enabled, UART already configured, menu visible.
; Draw the intro status line and enqueue 12 bytes of controller reset.
; Select a generated absolute-tick table and duration: 200 or 240 ticks.
; Returns to begin on completion, skip or mute; BREAK exits directly.
; Clobbers AF/BC/DE/HL; updates intro state and queue. No file access.
title_intro:
    ld hl,intromsg
    ld de,screen+840
    call text
    call present
    xor a
    ld (qcount),a
    ld (qpos),a
    ld (oldbass),a
    ld (oldupper),a
    ld hl,intro_setup
    ld de,queue
    ld bc,12
    ldir
    ld a,12
    ld (qcount),a
    ld hl,intro25
    ld b,200
    ld a,(musicrate)
    cp 5
    jp z,intro_clock
    ld hl,intro30
    ld b,240
intro_clock:
    ld (introptr),hl
    ld a,b
    ld (introlimit),a
    ld a,(0x4288)
    ld (introstart),a

; Pump one byte per iteration if ready, then check keyboard.
; Compute elapsed = (current TIMER$ - introstart) mod 256. The eight-second
; limit fits in one byte at either clock rate. Only load a new record when
; the prior queue is empty and its absolute deadline has arrived.
; Record layout: deadline, payload byte count, full MIDI messages.
; A zero count terminates. Timeout can bypass the last scheduled record;
; cleanup independently releases every pitch used by the intro.
intro_loop:
    call midi_pump
    ld a,(0x3840)
    bit 2,a
    jp nz,intro_break
    bit 1,a
    jp nz,intro_mute
    bit 7,a
    jp nz,intro_finish
    ld a,(0x4288)
    ld b,a
    ld a,(introstart)
    ld c,a
    ld a,b
    sub c
    ld b,a
    ld a,(introlimit)
    cp b
    jp z,intro_finish
    jp c,intro_finish
    ld a,(qcount)
    or a
    jp nz,intro_loop
    ld hl,(introptr)
    ld a,b
    cp (hl)
    jp c,intro_loop
    inc hl
    ld a,(hl)
    or a
    jp z,intro_finish
    ld (qcount),a
    ld c,a
    ld b,0
    inc hl
    ld de,queue
    ldir
    ld (introptr),hl
    jp intro_loop

; Drain pending bytes and release notes before disabling MIDI for this
; round. SPACE instead retains MIDI; BREAK cleans up then exits.
intro_mute:
    call intro_cleanup
    xor a
    ld (midi),a
    ret
intro_break:
    call intro_cleanup
    xor a
    ld (midi),a
    jp quit
intro_finish:
    call intro_cleanup
    ret
; On skip or timeout, drain queued bytes before sending explicit note-offs
; for every pitch used in the introduction. A stalled UART disables MIDI
; for this round instead of abandoning a partial MIDI message and continuing.

; Drain outstanding messages before enqueueing individual note-offs.
; This avoids splicing a new status byte into a partially sent message.
; intro_pitches lists every pitch used, followed by zero. Cleanup also
; resets pedals and sends CC123. On timeout, discard queue and disable MIDI.
; Delivery cannot be guaranteed if hardware is disconnected.
intro_cleanup:
    call intro_flush
    jp nz,intro_fault
    ld hl,intro_pitches
    ld (introptr),hl
intro_off_loop:
    ld hl,(introptr)
    ld a,(hl)
    or a
    jp z,intro_cc
    inc hl
    ld (introptr),hl
    ld (queue+1),a
    ld a,128
    ld (queue),a
    xor a
    ld (queue+2),a
    ld a,3
    ld (qcount),a
    call intro_flush
    jp nz,intro_fault
    jp intro_off_loop
intro_cc:
    ld hl,intro_setup
    ld de,queue
    ld bc,12
    ldir
    ld a,12
    ld (qcount),a
    call intro_flush
    ret z
intro_fault:
    xor a
    ld (midi),a
    ld (qcount),a
    ld (qpos),a
    ret

; Bounded foreground polling helper. Return Z if queue drained; NZ if
; 8192 pump attempts expire. BC is saved around midi_pump, which itself
; preserves BC. This is an iteration limit, not a measured time interval.
intro_flush:
    ld bc,8192
intro_flush_loop:
    push bc
    call midi_pump
    pop bc
    ld a,(qcount)
    or a
    ret z
    dec bc
    ld a,b
    or c
    jp nz,intro_flush_loop
    ld a,1
    or a
    ret

; ==========================================================================
; 04 / WAVE SETUP AND FRAME SCHEDULER
; ==========================================================================
; Initialise 35 aliens (five rows, seven columns), four two-row bunkers,
; player and projectiles. Formation starts at character (5,2) and uses
; five-pixel vertical spacing. UFO state is reset for each wave.
newwave:
    ld hl,aliens
    ld b,35
    ld a,1
init_alien:
    ld (hl),a
    inc hl
    djnz init_alien
    ld a,35
    ld (alive),a
    ld a,5
    ld (ax),a
    ld a,12
    ld (alienwait),a
    ld a,2
    ld (ay),a
    ld a,1
    ld (direction),a
    ld a,31
    ld (px),a
    ld a,20
    ld (bombwait),a
    ld a,100
    ld (ufowait),a
    xor a
    ld (ufox),a
    ld (anim),a
    ld (shoty),a
    ld (bomby),a
    ld (bombphase),a
    ld (fireheld),a
    ld (effect),a
    ld (cooldown),a
    ld hl,shield
    ld b,128
shield_clear:
    ld (hl),32
    inc hl
    djnz shield_clear
    ld hl,shield+5
    call make_shield
    ld hl,shield+21
    call make_shield
    ld hl,shield+37
    call make_shield
    ld hl,shield+53
    call make_shield
    call render
    ld a,(musiclive)
    or a
    jp nz,wave_clock_ready
    ld a,(0x4288)
    ld (musicclock),a
    ld a,1
    ld (musiclive),a
wave_clock_ready:
    ld a,(0x4288)
    ld (lasttick),a

; Wait for a change in TIMER$ while servicing one queued UART byte per pass.
; BREAK remains responsive during the wait. Run one update per observed tick;
; no catch-up for missed ticks. render also resolves player/alien collisions.
; If lives reach zero or formation base row reaches 7, end the game.
; If alive reaches zero, increment wave and initialise the next formation.
frame_wait:
    call music_service
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    ld a,(demo)
    or a
    jp z,frame_clock
    ld a,(0x3840)
    call demo_cancel
    jp nz,demo_end
frame_clock:
    ld a,(0x4288)
    ld b,a
    ld a,(lasttick)
    cp b
    jp z,frame_wait
    ld a,b
    ld (lasttick),a
    ld a,(demo)
    or a
    jp z,frame_play
    ld hl,(demoticks)
    dec hl
    ld (demoticks),hl
    ld a,h
    or l
    jp z,demo_end
frame_play:
    call player
    call advance_shot
    call music_service
    call advance_aliens
    ld a,(ay)
    cp 7
    jp nc,gameover
    call advance_bomb
    call advance_ufo
    call music_service
    call render
    call music_service
    call effect_play
    call music_service
    ld a,(lives)
    or a
    jp z,gameover
    ld a,(alive)
    or a
    jp nz,frame_wait
    ld a,(wave)
    inc a
    ld (wave),a
    jp newwave

; Copy six-cell upper and lower bunker silhouettes from original artwork.
; Bunker widths are 12 pixels; central notch in lower row. Each row is
; independently destructible at character-cell granularity.
make_shield:
    push hl
    ld d,h
    ld e,l
    ld hl,bunker_top
    ld bc,6
    ldir
    pop hl
    ld de,64
    add hl,de
    ld d,h
    ld e,l
    ld hl,bunker_bottom
    ld bc,6
    ldir
    ret

; Resolve a projectile against either shield row. A=projectile row,
; E=column, D=0. Return Z if no shield; NZ if a block was destroyed.
shield_hit:
    cp 11
    jp z,shield_top_hit
    cp 12
    jp nz,shield_miss
    ld hl,shield+64
    jp shield_lookup
shield_top_hit:
    ld hl,shield
shield_lookup:
    add hl,de
    ld a,(hl)
    cp 32
    ret z
    ld (hl),32
    ret
shield_miss:
    xor a
    ret

; ==========================================================================
; 05 / PLAYER AND PROJECTILES
; ==========================================================================
; Read active-high keyboard bits into B. Move one character per update;
; LEFT takes priority over RIGHT. px is left edge of a three-cell cannon
; (allowed 1..61). Fire is edge-triggered through fireheld, not auto-repeat.
; Only one laser at a time. shoty=0 means inactive.
player:
    ld a,(demo)
    or a
    jp z,player_keyboard
    call demo_keys
    jp player_input
player_keyboard:
    ld a,(0x3840)
player_input:
    ld b,a
    bit 5,b
    jp z,move_right
    ld a,(px)
    cp 1
    jp z,fire
    dec a
    ld (px),a
    jp fire
move_right:
    bit 6,b
    jp z,fire
    ld a,(px)
    cp 61
    jp z,fire
    inc a
    ld (px),a
fire:
    bit 7,b
    jp nz,fire_pressed
    xor a
    ld (fireheld),a
    ret

; Latch the key even if a shot already exists; release SPACE before firing
; again. Spawn at cannon centre (px+1), row 14. The next routine moves it
; up immediately; request effect 1 (laser chirp).
fire_pressed:
    ld a,(fireheld)
    or a
    ret nz
    ld a,1
    ld (fireheld),a
    ld a,(shoty)
    or a
    ret nz
    ld a,(px)
    inc a
    ld (shotx),a
    ld a,14
    ld (shoty),a
    ld a,1
    ld (effect),a
    ret

; Move active laser one character row. Bunkers absorb shots in either
; of their two rows. Formation and UFO collisions are resolved by render.
advance_shot:
    ld a,(shoty)
    or a
    ret z
    dec a
    ld (shoty),a
    ld b,a
    ld a,(shotx)
    ld e,a
    ld d,0
    ld a,b
    call shield_hit
    ret z
    xor a
    ld (shoty),a
    ret

; ==========================================================================
; 06 / ALIEN FORMATION
; ==========================================================================
; Move formation one character (two pixels) per step, seven columns
; spaced seven characters (14 pixels) apart. A separate animation flag
; toggles every movement, not only at direction reversal. Speed increases
; as population falls. Fixed base bounds 1..19 keep all sprites on screen.
advance_aliens:
    ld hl,alienwait
    dec (hl)
    ret nz
    ld a,(anim)
    xor 1
    ld (anim),a
    ld a,(alive)
    cp 28
    ld b,12
    jp nc,alien_speed
    cp 21
    ld b,9
    jp nc,alien_speed
    cp 14
    ld b,6
    jp nc,alien_speed
    cp 7
    ld b,4
    jp nc,alien_speed
    ld b,2
alien_speed:
    ld a,(wave)
    cp 2
    jp c,speed_set
    dec b
speed_set:
    ld a,b
    ld (alienwait),a
    ld a,(direction)
    or a
    jp z,left_step
    ld a,(ax)
    cp 19
    jp z,drop_left
    inc a
    ld (ax),a
    ret
left_step:
    ld a,(ax)
    cp 1
    jp z,drop_right
    dec a
    ld (ax),a
    ret
drop_left:
    xor a
    ld (direction),a
    jp drop
drop_right:
    ld a,1
    ld (direction),a
drop:
    ld hl,ay
    inc (hl)
    ret

; Mystery saucer traverses the top lane, one cell per game tick. It is
; independent of formation and shield collisions. 0 = not visible.
advance_ufo:
    ld a,(ufox)
    or a
    jp nz,ufo_move
    ld hl,ufowait
    dec (hl)
    ret nz
    ld a,1
    ld (ufox),a
    ret
ufo_move:
    inc a
    cp 61
    jp nc,ufo_reset
    ld (ufox),a
    ret
ufo_reset:
    xor a
    ld (ufox),a
    ld a,180
    ld (ufowait),a
    ret

; One enemy bomb at a time. Launch position chosen by render (a live alien).

; ==========================================================================
; 07 / ENEMY BOMB AND DAMAGE
; ==========================================================================
; Reduce invulnerability cooldown each update. At most one bomb active;
; bomby=0 means none. An idle bomb waits 20 ticks, then starts below the
; launch candidate recorded by the previous render. Active bombs advance
; one row per three updates.
advance_bomb:
    ld a,(cooldown)
    or a
    jp z,bomb_active
    dec a
    ld (cooldown),a
bomb_active:
    ld a,(bomby)
    or a
    jp nz,bomb_move
    ld hl,bombwait
    dec (hl)
    ret nz
    ld a,20
    ld (bombwait),a
    ld a,(launchy)
    or a
    ret z
    inc a
    ld (bomby),a
    ld a,(launchx)
    ld (bombx),a
    ld a,(bomby)
    cp 14
    jp nc,bomb_hit
    xor a
    ld (bombphase),a
    ld a,(bombx)
    ld e,a
    ld d,0
    ld a,(bomby)
    call shield_hit
    ret z
    xor a
    ld (bomby),a
    ret

; Bomb advances every third update; shield tests cover both rows.
bomb_move:
    ld hl,bombphase
    inc (hl)
    ld a,(hl)
    cp 3
    ret c
    ld (hl),0
    ld hl,bomby
    inc (hl)
    ld a,(hl)
    cp 14
    jp z,bomb_hit
    ld b,a
    ld a,(bombx)
    ld e,a
    ld d,0
    ld a,b
    call shield_hit
    ret z
    xor a
    ld (bomby),a
    ret


; Unsigned (bombx - px) < 3 is the cannon collision test. On hit, reduce
; lives, request damage effect 3 and set 30-tick invulnerability. The
; cooldown also controls the flashing player sprite in render.
bomb_hit:
    xor a
    ld (bomby),a
    ld a,(cooldown)
    or a
    ret nz
    ld a,(px)
    ld b,a
    ld a,(bombx)
    sub b
    cp 3
    ret nc
    ld hl,lives
    dec (hl)
    ld a,3
    ld (effect),a
    ld a,30
    ld (cooldown),a
    ret
; Buffer address from row B, column C. Clobbers DE, HL; preserves BC.

; ==========================================================================
; 08 / GRAPHICS PRIMITIVES
; ==========================================================================
; Input B=row 0..15, C=column 0..63. Output HL=screen+B*64+C.
; Preserves BC and A; clobbers DE and flags. No coordinate bounds check.
; Uses six 16-bit doublings to multiply by 64.
cell:
    ld l,b
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld e,c
    ld d,0
    add hl,de
    ld de,screen
    add hl,de
    ret

; Fill entire back buffer with ASCII 32 using 16 unrolled stores per pass.
; 64 iterations; preserves A, clobbers BC/HL and flags (DE unchanged).
; Avoids 1023 repeated LDIR transfers and never borrows the stack pointer.
blank:
    ld c,a
    ld a,32
    ld hl,screen
    ld b,64
blank_block:
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    djnz blank_block
    ld a,c
    ret

; Full 1024-byte back-buffer blit: 32 LDI instructions per block.
; LDI sets P/V if BC remains nonzero; final JP PE repeats until BC=0.
; No interrupt masking or stack tricks. A preserved, BC/DE/HL clobbered.
present:
    ld hl,screen
    ld de,0x3c00
    ld bc,1024
present_block:
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    jp pe,present_block
    ret

; Input HL=zero-terminated string, DE=destination buffer address.
; Copy bytes up to (not including) the terminator. On return HL points
; to terminator, DE to next free cell, A=0, Z set. No bounds check.
text:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    jp text

; ==========================================================================
; 09 / FRAME COMPOSITION AND COLLISIONS
; ==========================================================================
; Draw HUD, two rows of shields, 35 aliens, mystery ship and projectiles.
; Each alien uses original 6x3-pixel art. Its Y position is 5 pixels per
; row: table offsets [0,1,3,5,6], phases [0,2,1,0,2]. Each packed sprite
; has 3 cells in the first row and 3 in the second (space mask = skip).
; Collision is approximate character-cell bounding boxes, not pixel-perfect.
render:
    call blank
    ld hl,hud
    ld de,screen+1
    call text
    ld hl,score
    ld de,screen+7
    ld bc,4
    ldir
    ld hl,hiscore
    ld de,screen+16
    ld bc,4
    ldir
    ld a,(lives)
    add a,48
    ld (screen+28),a
    ld a,(wave)
    and 15
    cp 10
    jp c,wave_digit
    add a,7
wave_digit:
    add a,48
    ld (screen+36),a
    ld a,(demo)
    or a
    jp z,render_shields
    ld hl,demohud
    ld de,screen+39
    call text
render_shields:
    ld hl,shield
    ld de,screen+704
    ld bc,128
    ldir
    xor a
    ld (launchy),a
    ld (rowindex),a
    ld hl,aliens
    ld (flagptr),hl
row_loop:
    ; Service between formation rows, with no live register dependencies.
    ld a,(musiclive)
    or a
    jp z,row_audio_done
    call music_service
row_audio_done:
    ld a,(rowindex)
    ld e,a
    ld d,0
    ld hl,row_offsets
    add hl,de
    ld b,(hl)
    ld a,(ay)
    add a,b
    ld (rowy),a
    ld hl,row_phases
    add hl,de
    ld a,(hl)
    ld (phase),a
    ld a,(rowindex)
    ld e,a
    ld d,0
    ld hl,sprite_rows
    add hl,de
    ld a,(hl)
    ld b,a
    ld a,(anim)
    or a
    jp z,sprite_phase
    ld a,b
    add a,3
    ld b,a
sprite_phase:
    ld a,(phase)
    add a,b
    add a,a
    ld e,a
    ld d,0
    ld hl,sprite_ptrs
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,row_sprite
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(ax)
    ld (colx),a
    ld c,a
    ld a,(rowy)
    ld b,a
    call cell
    ld (row_dest),hl
    ; Shot can only intersect this row if its Y matches an occupied row.
    ; Cache the result, avoiding repeated Y comparisons for seven aliens.
    xor a
    ld (row_shot),a
    ld a,(shoty)
    or a
    jp z,row_ready
    ld b,a
    ld a,(rowy)
    cp b
    jp z,row_shot_match
    ld a,(phase)
    or a
    jp z,row_ready
    ld a,(rowy)
    inc a
    cp b
    jp nz,row_ready
row_shot_match:
    ld a,1
    ld (row_shot),a
row_ready:
    ld a,7
    ld (colleft),a
alien_loop:
    ld hl,(flagptr)
    ld a,(hl)
    or a
    jp z,next_alien
    ld a,(row_shot)
    or a
    jp z,draw_alien
check_alien_x:
    ld a,(colx)
    ld b,a
    ld a,(shotx)
    sub b
    cp 3
    jp nc,draw_alien
    ld (hl),0
    xor a
    ld (shoty),a
    ld (row_shot),a  ; One projectile can destroy only one alien.
    ld hl,alive
    dec (hl)
    ld a,2
    ld (effect),a
    ld a,(rowindex)
    ld e,a
    ld d,0
    ld hl,point_table
    add hl,de
    ld a,(hl)
    call score_add
    jp next_alien

; The row loop caches a packed sprite pointer once per row, selected
; by row type, animation frame and fractional vertical phase.
draw_alien:
    ld de,(row_sprite)
    ld hl,(row_dest)
    call draw_sprite

; Use bottom occupied sprite row as candidate bomb origin. Prefer
; an alien to the left of the player; retain the first as fallback.
launch_candidate:
    ld a,(launchy)
    or a
    jp z,save_launch
    ld a,(colx)
    ld c,a
    ld a,(px)
    cp c
    jp c,next_alien
save_launch:
    ld a,(rowy)
    ld b,a
    ld a,(phase)
    or a
    jp z,save_launch_row
    inc b
save_launch_row:
    ld a,b
    ld (launchy),a
    ld a,(colx)
    inc a
    ld (launchx),a
next_alien:
    ld hl,(flagptr)
    inc hl
    ld (flagptr),hl
    ld hl,(row_dest)
    ld de,7
    add hl,de
    ld (row_dest),hl
    ld a,(colx)
    add a,7
    ld (colx),a
    ld hl,colleft
    dec (hl)
    jp nz,alien_loop
    ld hl,rowindex
    inc (hl)
    ld a,(hl)
    cp 5
    jp nz,row_loop
    call render_ufo
    ld a,(shoty)
    or a
    jp z,render_bomb
    ld b,a
    ld a,(shotx)
    ld c,a
    call cell
    ld (hl),149
    jp render_bomb

; Merge packed masks into existing buffer; preserve shield overlap semantics.
; Input HL=destination, DE=6-byte mask; phase is current row's phase.
; Phase 0 has no second-row pixels (all such masks end in 32,32,32).
; Unroll each three-cell line to remove DJNZ loop overhead.
; Clobbers AF,BC,DE,HL. Only called by draw_alien.
draw_sprite:
    ld a,(rowy)
    cp 10
    jp c,sprite_fast
    call sprite_line
    ld a,(phase)
    or a
    ret z
    push de
    ld de,61
    add hl,de
    pop de
    jp sprite_line
sprite_line:
    ld a,(de)
    cp 32
    jp z,sprite_skip0
    ld c,a
    ld a,(hl)
    cp 32
    jp nz,sprite_merge0
    ld a,128
sprite_merge0:
    or c
    ld (hl),a
sprite_skip0:
    inc hl
    inc de
    ld a,(de)
    cp 32
    jp z,sprite_skip1
    ld c,a
    ld a,(hl)
    cp 32
    jp nz,sprite_merge1
    ld a,128
sprite_merge1:
    or c
    ld (hl),a
sprite_skip1:
    inc hl
    inc de
    ld a,(de)
    cp 32
    jp z,sprite_skip2
    ld c,a
    ld a,(hl)
    cp 32
    jp nz,sprite_merge2
    ld a,128
sprite_merge2:
    or c
    ld (hl),a
sprite_skip2:
    inc hl
    inc de
    ret

; Fast path: row < 10, both rows are clear of bunkers (rows 11/12).
; The formation geometry gives each alien exclusive character cells.
; Direct copy of space-padded masks is equivalent to the OR merge.
; HL=destination, DE=source on entry; swap for LDI. No live BC value.
sprite_fast:
    ex de,hl
    ldi
    ldi
    ldi
    ld a,(phase)
    or a
    ret z
    ex de,hl
    ld bc,61
    add hl,bc
    ex de,hl
    ldi
    ldi
    ldi
    ret

; Mystery ship on row 1. Award 500 points if the laser hits its four-cell
; bounding box. The ship art is original. No bonus sound beyond hit FX.
render_ufo:
    ld a,(ufox)
    or a
    ret z
    ld c,a
    ld a,(shoty)
    cp 1
    jp nz,ufo_draw
    ld a,(shotx)
    sub c
    cp 4
    jp nc,ufo_draw
    xor a
    ld (shoty),a
    call ufo_reset
    ld a,2
    ld (effect),a
    ld b,5
ufo_bonus:
    push bc
    ld a,100
    call score_add
    pop bc
    djnz ufo_bonus
    ret
ufo_draw:
    ld b,1
    call cell
    ld (hl),148
    inc hl
    ld (hl),191
    inc hl
    ld (hl),191
    inc hl
    ld (hl),168
    ret

; Draw projectiles after formation; laser 149, bomb 168. Active sprites
; use row nonzero. Player at row 14 uses three codes 176,189,176; hide it
; when cooldown bit 1 is set. Floor row 15 is a thin line, code 131.
render_bomb:
    ld a,(bomby)
    or a
    jp z,render_player
    ld b,a
    ld a,(bombx)
    ld c,a
    call cell
    ld (hl),168
render_player:
    ld a,(cooldown)
    bit 1,a
    jp nz,render_floor
    ld b,14
    ld a,(px)
    ld c,a
    call cell
    ld (hl),176
    inc hl
    ld (hl),189
    inc hl
    ld (hl),176
render_floor:
    ld hl,screen+960
    ld b,64
floor_loop:
    ld (hl),131
    inc hl
    djnz floor_loop
    jp present

; A=points (1..100). Add to four ASCII decimal digits directly.
; Convert each sum into a digit and carry by subtracting ten at most
; ten times on the units digit and at most once on later digits.
; Discard carry beyond thousands (same 10000 wrap as v0.4).
; Update high score after the addition; retain the five separate 100-point
; additions for UFO hits so high-score behavior across wrap is unchanged.
score_add:
    ld hl,score+3
    ld b,4
score_digit:
    add a,(hl)
    sub 48
    ld c,0
score_reduce:
    cp 10
    jp c,score_store
    sub 10
    inc c
    jp score_reduce
score_store:
    add a,48
    ld (hl),a
    ld a,c
    or a
    jp z,score_done
    dec hl
    djnz score_digit
score_done:
    ld a,(demo)
    or a
    ret nz                    ; Demo scores never enter session high score.
    ld hl,score
    ld de,hiscore
    ld b,4
hi_compare:
    ld a,(de)
    cp (hl)
    jp c,hi_replace
    ret nz
    inc hl
    inc de
    djnz hi_compare
    ret
hi_replace:
    ld hl,score
    ld de,hiscore
    ld bc,4
    ldir
    ret

; Cassette effects: short square-wave sweeps, no long delay loops.
; Interrupts stay enabled; pitch is approximate. 8-18 cycles per effect.

; ==========================================================================
; 10 / CASSETTE SOUND EFFECTS
; ==========================================================================
; Consume one pending effect ID (1 shot, 2 alien hit, 3 player damage).
; Later events in the same frame can overwrite earlier ones. Select cycle
; count C and initial half-period loop count D. Output 1 then 0 to FFH,
; with DJNZ delays; increase D each cycle for a descending pitch sweep.
; Short but blocking, no interrupt masking. Actual sound pitch depends on
; CPU clock and interrupt overhead. Returns with cassette output low.
effect_play:
    ld a,(demo)
    or a
    jp z,effect_normal
    xor a
    ld (effect),a
    ret                       ; Silent attract mode.
effect_normal:
    ld a,(effect)
    or a
    ret z
    ld b,a
    xor a
    ld (effect),a
    ld a,b
    cp 1
    jp z,fx_shot
    cp 2
    jp z,fx_hit
    ld c,18
    ld d,22
    jp tone
fx_shot:
    ld c,10
    ld d,8
    jp tone
fx_hit:
    ld c,14
    ld d,13
tone:
    ld a,1
    out (0xff),a
    ld b,d
tone_high:
    djnz tone_high
    xor a
    out (0xff),a
    ld b,d
tone_low:
    djnz tone_low
    inc d
    dec c
    jp nz,tone
    ret
; MIDI queue: send only if transmitter ready; never wait in gameplay.
; 12 MIDI bytes per beat, plus one tick token in timed mode.

; ==========================================================================
; 11 / NON-BLOCKING RS-232 MIDI QUEUE
; ==========================================================================
; If qcount=0, return immediately. Otherwise poll EA bit 6 once; if not
; ready, return without changing state. Send queue[qpos] to EB, increment
; qpos and decrement qcount. Reset qpos to zero after the final byte.
; This is a single pending batch, not a circular FIFO. Producers must wait
; for qcount=0; queue capacity 18 bytes. Clobbers AF/DE/HL, preserves BC.
; No parsing, ASCII conversion or line endings: full binary MIDI status
; bytes are transmitted. The external bridge handles MIDI baud conversion.
midi_pump:
    ld a,(qcount)
    or a
    ret z
    in a,(0xea)
    and 64
    ret z
    ld a,(qpos)
    ld e,a
    ld d,0
    ld hl,queue
    add hl,de
    ld a,(hl)
    out (0xeb),a
    ld hl,qpos
    inc (hl)
    ld hl,qcount
    dec (hl)
    ret nz
    xor a
    ld (qpos),a
    ret

; Foreground audio service: independent of game update count. Safe only
; between routines: AF/BC/DE/HL are volatile. No waiting for UART.
music_service:
    ld a,(midi)
    or a
    ret z
    call midi_pump
    ; Consume at most one elapsed clock tick per call, and never overwrite
    ; a pending batch. Repeated calls catch up on ticks missed by rendering.
music_tick:
    ld a,(midi)
    or a
    ret z
    ld a,(qcount)
    or a
    ret nz
    ld a,(musicclock)
    ld b,a
    ld a,(0x4288)
    cp b
    ret z
    ; Increment the logical clock, rather than replacing it with 'now'.
    ; Unsigned byte wrap is intentional (service must occur within 256 ticks).
    ld hl,musicclock
    inc (hl)
    ld a,(musicwait)
    dec a
    ld (musicwait),a
    jp z,music_due
    ld a,(streaming)
    or a
    ret z
    ; Send tick tokens even during rests to keep Nano deadlines advancing.
    ld a,248                  ; F8: next transport tick.
    ld (queue),a
    ld a,1
    ld (qcount),a
    ret

; Read one bass and one upper pitch from parallel 16-entry tables.
; Queue 80 oldbass 00, 80 oldupper 00, 90 bass 50, 90 upper 44 (hex).
; Both voices are channel 1: EMT-10 Bass Split routes notes by pitch.
; Initial old pitches are zero (harmless note-offs at first beat). Advance
; index modulo 16, record new pitches, publish qcount last.
; Recalculate the interval at each note pair from formation depth.
; musicrate remains the clock selector, not the adaptive tempo.
music_due:
    call music_interval
    ld (musicwait),a
    ld a,(musicindex)
    ld e,a
    ld d,0
    ld hl,bassline
    add hl,de
    ld b,(hl)
    ld hl,leadline
    add hl,de
    ld c,(hl)
    ld hl,queue
    ld a,(streaming)
    or a
    jp z,music_payload
    ld (hl),248               ; Tick token must precede its MIDI payload.
    inc hl
music_payload:
    ld (hl),128
    inc hl
    ld a,(oldbass)
    ld (hl),a
    inc hl
    ld (hl),0
    inc hl
    ld (hl),128
    inc hl
    ld a,(oldupper)
    ld (hl),a
    inc hl
    ld (hl),0
    inc hl
    ld (hl),144
    inc hl
    ld (hl),b
    inc hl
    ld (hl),80
    inc hl
    ld (hl),144
    inc hl
    ld (hl),c
    inc hl
    ld (hl),68
    ld a,b
    ld (oldbass),a
    ld a,c
    ld (oldupper),a
    ld a,(musicindex)
    inc a
    and 15
    ld (musicindex),a
    ld a,(streaming)
    add a,12
    ld (qcount),a
    ret
; Adaptive soundtrack: ay=2 starts a wave; ay=6 is the last playable
; depth before game over at ay=7. Clamp for defensive use and tests.
; 25/30 Hz tables approximate the same rising pulse rate. A new wave
; restores normal tempo at the next beat without resetting melody phase.
; Output A=interval (2..6 ticks). Clobbers AF/DE/HL, no UART side effects.
music_interval:
    ld a,(ay)
    cp 2
    jp nc,tempo_min_ok
    ld a,2
tempo_min_ok:
    cp 7
    jp c,tempo_max_ok
    ld a,6
tempo_max_ok:
    sub 2
    ld e,a
    ld d,0
    ld hl,tempo25
    ld a,(musicrate)
    cp 5
    jp z,tempo_lookup
    ld hl,tempo30
tempo_lookup:
    add hl,de
    ld a,(hl)
    ret

; Drain pending data and send pedal off + All Notes Off on exit.
; Bounded polling; no serial hardware cannot trap the game.

; ==========================================================================
; 12 / AUDIO CLEANUP AND EXIT
; ==========================================================================
; If enabled, drain current batch (up to 8192 attempts). If it cannot
; drain, return without splicing a new message. Otherwise queue explicit
; last bass/upper note-offs and four controller resets; bounded drain.
; No UART fault can trap the game here, but note delivery is not assured.
; Does not restore the prior serial configuration or disable MIDI itself.
midi_stop:
    ld a,(midi)
    or a
    ret z
    ld a,(streaming)
    or a
    jp z,stop_raw
    ; FC cancels pending timed notes even between bytes of a message.
    xor a
    ld (qpos),a
    ld a,252
    ld (queue),a
    ld a,1
    ld (qcount),a
    call intro_flush
    xor a
    ld (streaming),a
    ret
stop_raw:
    ld bc,8192
flush_loop:
    push bc
    call midi_pump
    pop bc
    ld a,(qcount)
    or a
    jp z,flush_done
    dec bc
    ld a,b
    or c
    jp nz,flush_loop
    ret
flush_done:
stop_cleanup:
    ld hl,cleanup_midi
    ld de,queue
    ld bc,18
    ldir
    ld a,(oldbass)
    ld (queue+1),a
    ld a,(oldupper)
    ld (queue+4),a
    ld a,18
    ld (qcount),a
    ld bc,8192
stop_loop:
    push bc
    call midi_pump
    pop bc
    ld a,(qcount)
    or a
    ret z
    dec bc
    ld a,b
    or c
    jp nz,stop_loop
    ret

; Stop music, clear enable, draw final score and menu prompt. No game-over
; music yet. ENTER returns to the title, BREAK exits; no disk score saving.
gameover:
    ld a,(demo)
    or a
    jp nz,demo_end
    call midi_stop
    xor a
    ld (midi),a
    call blank
    ld hl,overmsg
    ld de,screen+339
    call text
    ld hl,scoremsg
    ld de,screen+467
    call text
    ld hl,score
    ld de,screen+479
    ld bc,4
    ldir
    ld hl,againmsg
    ld de,screen+585
    call text
    call present
again:
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    bit 0,a
    jp z,again
    jp menu

; Attempt MIDI cleanup, force cassette output low, clear physical video
; RAM, restore caller SP, jump to LDOS 402D. Does not restore the previous
; screen contents or UART configuration.
quit:
    call midi_stop
    xor a
    out (0xff),a
    ld hl,0x3c00
    ld (hl),32
    ld de,0x3c01
    ld bc,1023
    ldir
    ld sp,(savedsp)
    jp 0x402d
; Strings (zero terminated)

; ==========================================================================
; 13 / CONSTANTS AND EMBEDDED MUSIC
; ==========================================================================
; Text strings are ASCII with a zero terminator. Offsets used by text
; callers are measured in character cells, not pixels.
title: db "S T A R   S I E G E",0
pointsmsg: db "25 / 20 / 10   MYSTERY 500",0
help1: db "LEFT / RIGHT = MOVE   SPACE = FIRE",0
help2: db "2/3 RAW 25/30HZ  4/5 BUFFERED 25/30HZ",0
help3: db "ENTER = TITLE MUSIC   CLEAR = FX ONLY",0
help4: db "BREAK = QUIT   DESTROY THE INVADERS",0
demomsg: db "SPACE = DEMO / AUTO AFTER 6 SEC",0
demohud: db "DEMO - KEY FOR MENU",0
; 19 characters plus terminator each; show_audio_mode relies on stride 20.
raw25msg: db "RAW 25HZ           ",0
raw30msg: db "RAW 30HZ           ",0
buf25msg: db "BUFFERED 25HZ      ",0
buf30msg: db "BUFFERED 30HZ      ",0
demo_lanes: db 13,29,45,59
intromsg: db "INTRO: SPACE = SKIP   CLEAR = MUTE",0
hud: db "SCORE:0000  HI:0000  LIVES:0  WAVE:0",0
overmsg: db "G A M E   O V E R",0
scoremsg: db "FINAL SCORE:",0
againmsg: db "ENTER = MENU       BREAK = EXIT",0
; Original two-part ostinato; program 71 = Electric Bass + Brass.

; Parallel original 16-step melodies. Bass pitches below MIDI 55; upper
; pitches at/above 55. Native program 71 (C0 47 hex) selects Electric Bass
; + Brass. The intro uses program 55 (C0 37): Upright Bass + Brass.
; These are EMT-10 native patches, not General MIDI program numbers.

; Original six-pixel-wide, three-pixel-high sprite artwork.
row_offsets: db 0,1,3,5,6
row_phases: db 0,2,1,0,2
sprite_rows: db 0,6,6,12,12
point_table: db 25,20,20,10,10
bunker_top: db 188,191,191,191,191,188
bunker_bottom: db 191,191,131,131,191,191
sprite_ptrs:
    dw art0_0,art0_1,art0_2
    dw art1_0,art1_1,art1_2
    dw art2_0,art2_1,art2_2
    dw art3_0,art3_1,art3_2
    dw art4_0,art4_1,art4_2
    dw art5_0,art5_1,art5_2
art0_0: db 152,191,164,32,32,32
art0_1: db 160,188,144,129,131,130
art0_2: db 32,176,32,134,143,137
art1_0: db 172,143,156,32,32,32
art1_1: db 176,188,176,130,32,129
art1_2: db 32,176,32,139,131,135
art2_0: db 173,188,158,32,32,32
art2_1: db 180,176,184,130,131,129
art2_2: db 144,32,160,139,143,135
art3_0: db 158,140,173,32,32,32
art3_1: db 184,176,180,129,32,130
art3_2: db 160,32,144,135,131,139
art4_0: db 150,143,169,32,32,32
art4_1: db 152,188,164,129,32,130
art4_2: db 160,176,144,133,131,138
art5_0: db 174,131,157,32,32,32
art5_1: db 184,140,180,130,32,129
art5_2: db 160,176,144,139,32,135

tempo25: db 5,4,3,3,2          ; Formation ay=2..6; 200..80 ms.
tempo30: db 6,5,4,3,2          ; Formation ay=2..6; 200..67 ms.
bassline: db 36,36,43,36,39,39,46,39,41,41,48,41,38,38,45,38
leadline: db 67,72,70,74,70,75,74,77,72,77,75,79,69,74,72,67

; 14 bytes: CC64,66,67,123 value 0, then program change 71.
; cleanup_midi is 18 bytes with two placeholder note-offs; patched at exit.
; intro_setup is the same four controller resets without a patch change.
setup_midi: db 176,64,0,176,66,0,176,67,0,176,123,0,192,71
cleanup_midi: db 128,0,0,128,0,0,176,64,0,176,66,0,176,67,0,176,123,0
intro_setup: db 176,64,0,176,66,0,176,67,0,176,123,0
; Auto-generated by embed_intro.py. Do not edit these records by hand.
; Each record: absolute timer tick, byte count (<=18), MIDI payload.
; Count zero = end marker. intro_pitches is a zero-terminated cleanup list.
; BEGIN GENERATED INTRO TABLES
intro25:
    db 0,5,192,55,144,36,86
    db 9,3,128,36,0
    db 13,3,144,36,67
    db 22,3,128,36,0
    db 25,3,144,39,67
    db 34,3,128,39,0
    db 38,3,144,35,67
    db 47,3,128,35,0
    db 50,6,144,36,86,144,60,91
    db 59,3,128,36,0
    db 60,3,128,60,0
    db 63,6,144,43,67,144,63,91
    db 72,3,128,43,0
    db 73,3,128,63,0
    db 75,6,144,39,67,144,67,91
    db 84,3,128,39,0
    db 85,3,128,67,0
    db 88,6,144,35,67,144,70,91
    db 97,3,128,35,0
    db 98,3,128,70,0
    db 100,12,144,36,86,144,60,100,144,63,100,144,67,100
    db 109,3,128,36,0
    db 112,9,128,60,0,128,63,0,128,67,0
    db 113,3,144,36,67
    db 122,3,128,36,0
    db 125,12,144,41,67,144,62,100,144,65,100,144,70,100
    db 134,3,128,41,0
    db 137,9,128,62,0,128,65,0,128,70,0
    db 138,3,144,43,67
    db 147,3,128,43,0
    db 150,6,144,38,86,144,70,91
    db 159,3,128,38,0
    db 160,3,128,70,0
    db 163,6,144,35,67,144,67,91
    db 172,3,128,35,0
    db 173,3,128,67,0
    db 175,6,144,36,67,144,63,91
    db 184,3,128,36,0
    db 185,3,128,63,0
    db 188,15,144,36,67,144,60,100,144,63,100,144,67,100,144,72,100
    db 197,3,128,36,0
    db 199,12,128,60,0,128,63,0,128,67,0,128,72,0
    db 200,3,176,123,0
    db 200,0
intro30:
    db 0,5,192,55,144,36,86
    db 11,3,128,36,0
    db 15,3,144,36,67
    db 26,3,128,36,0
    db 30,3,144,39,67
    db 41,3,128,39,0
    db 45,3,144,35,67
    db 56,3,128,35,0
    db 60,6,144,36,86,144,60,91
    db 71,3,128,36,0
    db 73,3,128,60,0
    db 75,6,144,43,67,144,63,91
    db 86,3,128,43,0
    db 88,3,128,63,0
    db 90,6,144,39,67,144,67,91
    db 101,3,128,39,0
    db 103,3,128,67,0
    db 105,6,144,35,67,144,70,91
    db 116,3,128,35,0
    db 118,3,128,70,0
    db 120,12,144,36,86,144,60,100,144,63,100,144,67,100
    db 131,3,128,36,0
    db 134,9,128,60,0,128,63,0,128,67,0
    db 135,3,144,36,67
    db 146,3,128,36,0
    db 150,12,144,41,67,144,62,100,144,65,100,144,70,100
    db 161,3,128,41,0
    db 164,9,128,62,0,128,65,0,128,70,0
    db 165,3,144,43,67
    db 176,3,128,43,0
    db 180,6,144,38,86,144,70,91
    db 191,3,128,38,0
    db 193,3,128,70,0
    db 195,6,144,35,67,144,67,91
    db 206,3,128,35,0
    db 208,3,128,67,0
    db 210,6,144,36,67,144,63,91
    db 221,3,128,36,0
    db 223,3,128,63,0
    db 225,15,144,36,67,144,60,100,144,63,100,144,67,100,144,72,100
    db 236,3,128,36,0
    db 239,12,128,60,0,128,63,0,128,67,0,128,72,0
    db 240,3,176,123,0
    db 240,0
intro_pitches: db 35,36,38,39,41,43,60,62,63,65,67,70,72,0
; END GENERATED INTRO TABLES

; ==========================================================================
; 14 / MUTABLE STATE AND WORKSPACE
; ==========================================================================
; All scalar state is in RAM, initialised as needed. Word values use
; Z80 little-endian storage. See individual declarations below.
introptr: dw 0                  ; Current intro table or cleanup pitch-list pointer (word).
introstart: db 0                ; Timer low byte at intro start.
introlimit: db 0                ; 200/240 tick deadline.
menutick: db 0                 ; Menu idle timer origin.
demo: db 0                     ; 1 = automatic attract game.
demogate: db 0                 ; Ignore launch key until release.
demoindex: db 0                ; Next patrol lane index.
demoticks: dw 0                ; Remaining observed game updates.
savedsp: dw 0                   ; Original LDOS stack pointer.
midi: db 0                      ; 0=cassette only, 1=MIDI enabled.
musicrate: db 6                 ; Ticks per gameplay note pair (5/6).
musicwait: db 0                 ; LDOS ticks to next pair.
musicclock: db 0                ; Last consumed LDOS tick (modulo 256).
musiclive: db 0                 ; Set after first render, retained across waves.
buffered: db 0                  ; Menu selection: 1 requires timed Nano firmware.
streaming: db 0                 ; Active timed gameplay stream, never during title.
musicindex: db 0                ; Index 0..15 into both melody tables.
oldbass: db 0                   ; Last queued bass pitch.
oldupper: db 0                  ; Last queued upper pitch.
qcount: db 0                    ; Remaining bytes in pending queue, 0=empty.
qpos: db 0                      ; Offset of next byte to transmit.
lasttick: db 0                  ; Previous observed timer low byte.
lives: db 3                     ; Remaining player lives.
wave: db 1                      ; Wave counter (byte, HUD shows low nibble).
score: db 48,48,48,48           ; Four ASCII decimal digits.
hiscore: db 48,48,48,48         ; Session high score; retained across menu.
px: db 0                        ; Leftmost player column (1..61).
shotx: db 0                     ; Laser column.
shoty: db 0                     ; Laser row, zero=inactive.
fireheld: db 0                  ; SPACE edge-detection latch.
ax: db 0                        ; Left edge of formation base (1..19).
ay: db 0                        ; Top row of formation.
direction: db 0                 ; 0=left, 1=right.
alienwait: db 0                 ; Countdown to next formation movement.
alive: db 0                     ; Remaining live alien count.
bombx: db 0                     ; Enemy bomb column.
bomby: db 0                     ; Enemy bomb row, zero=inactive.
bombwait: db 0                  ; Countdown before next launch.
bombphase: db 0                 ; Subcounter for three-tick bomb movement.
launchx: db 0                   ; Candidate firing column from last render.
launchy: db 0                   ; Candidate firing row, zero=no candidate.
cooldown: db 0                  ; Player invulnerability/blink countdown.
effect: db 0                    ; Pending cassette effect ID, zero=none.
rowindex: db 0                  ; Current formation row index.
rowy: db 0                      ; Current top character row.
colx: db 0                      ; Current alien left column.
colleft: db 0                   ; Remaining aliens to scan in current row.
phase: db 0                     ; Pixel Y offset within a character row.
anim: db 0                      ; Alternate alien artwork every step.
ufox: db 0                      ; Mystery saucer column, 0=inactive.
ufowait: db 100                 ; Countdown to saucer appearance.
row_dest: dw 0                  ; Cached destination, advances seven cells per alien.
row_shot: db 0                  ; Current row can intersect active laser.
row_sprite: dw 0                ; Cached packed sprite pointer for current row.
flagptr: dw 0                   ; Pointer to current presence flag.
queue: ds 18                    ; 18-byte linear UART batch.
aliens: ds 35                   ; 5 rows x 7 live flags.
shield: ds 128                  ; Two rows, each 64 cells.
screen: ds 1024                 ; 64*16 off-screen character buffer.
stack: ds 128                   ; 128-byte private descending stack storage.
stacktop:                       ; Initial SP points just above stack allocation.
