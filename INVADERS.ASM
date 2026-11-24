; STAR SIEGE - original Space Invaders-style game
; Model III / LDOS 5.3.1, 64x16 display, 25/30 Hz TIMER$ at 4288h.
; Arrow keys, SPACE, BREAK. Optional 9600 baud MIDI bridge.
; No ROM graphics or DOS disk calls in the game loop. MIT.
org 0x6000
start:
    ld (savedsp),sp
    ld sp,stacktop
    xor a
    ld (midi),a
    out (0xff),a
menu:
    call blank
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
    call present
menu_wait:
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    ld a,(0x3810)
    bit 2,a
    jp nz,clock25
    bit 3,a
    jp z,menu_wait
    ld a,6
    jp clock_set
clock25:
    ld a,5
clock_set:
    ld (musicrate),a
    ; Enter = MIDI enabled; CLEAR = cassette-only.
mode_wait:
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    bit 1,a
    jp nz,begin
    bit 0,a
    jp z,mode_wait
    ld a,1
    ld (midi),a
    xor a
    out (0xe8),a
    ld a,0xee
    out (0xe9),a
    ld a,0x6f
    out (0xea),a
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
    ld (musicwait),a
    ld (oldbass),a
    ld (oldupper),a
    ld a,(midi)
    or a
    jp z,newwave
    ld hl,setup_midi
    ld de,queue
    ld bc,14
    ldir
    ld a,14
    ld (qcount),a
newwave:
    ld hl,aliens
    ld b,24
    ld a,1
init_alien:
    ld (hl),a
    inc hl
    djnz init_alien
    ld a,24
    ld (alive),a
    ld a,8
    ld (ax),a
    ld (alienwait),a
    ld a,2
    ld (ay),a
    ld a,1
    ld (direction),a
    ld a,31
    ld (px),a
    ld a,20
    ld (bombwait),a
    xor a
    ld (shoty),a
    ld (bomby),a
    ld (bombphase),a
    ld (fireheld),a
    ld (effect),a
    ld (cooldown),a
    ld hl,shield
    ld b,64
shield_clear:
    ld (hl),32
    inc hl
    djnz shield_clear
    ld hl,shield+10
    call make_shield
    ld hl,shield+29
    call make_shield
    ld hl,shield+48
    call make_shield
    call render
    ld a,(0x4288)
    ld (lasttick),a
frame_wait:
    call midi_pump
    ld a,(0x3840)
    bit 2,a
    jp nz,quit
    ld a,(0x4288)
    ld b,a
    ld a,(lasttick)
    cp b
    jp z,frame_wait
    ld a,b
    ld (lasttick),a
    call player
    call advance_shot
    call advance_aliens
    ld a,(ay)
    cp 10
    jp nc,gameover
    call advance_bomb
    call render
    call effect_play
    call music_tick
    call midi_pump
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
make_shield:
    ld b,6
shield_fill:
    ld (hl),191
    inc hl
    djnz shield_fill
    ret
; Controls: one character step per frame, one shot at a time.
player:
    ld a,(0x3840)
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
advance_shot:
    ld a,(shoty)
    or a
    ret z
    dec a
    ld (shoty),a
    cp 11
    ret nz
    ld a,(shotx)
    ld e,a
    ld d,0
    ld hl,shield
    add hl,de
    ld a,(hl)
    cp 32
    ret z
    ld (hl),32
    xor a
    ld (shoty),a
    ret
advance_aliens:
    ld hl,alienwait
    dec (hl)
    ret nz
    ; Increase speed as aliens are killed: 8, 6, 4, 2 ticks.
    ld a,(alive)
    cp 19
    ld b,8
    jp nc,alien_speed
    cp 13
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
    cp 20
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
; One enemy bomb at a time. Launch position chosen by render (a live alien).
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
    xor a
    ld (bombphase),a
    ret
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
    cp 11
    ret nz
    ld a,(bombx)
    ld e,a
    ld d,0
    ld hl,shield
    add hl,de
    ld a,(hl)
    cp 32
    ret z
    ld (hl),32
    xor a
    ld (bomby),a
    ret
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
blank:
    ld hl,screen
    ld (hl),32
    ld de,screen+1
    ld bc,1023
    ldir
    ret
present:
    ld hl,screen
    ld de,0x3c00
    ld bc,1024
    ldir
    ret
text:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    jp text
render:
    call blank
    ld hl,hud
    ld de,screen+1
    call text
    ld hl,score
    ld de,screen+7
    ld bc,4
    ldir
    ld a,(lives)
    add a,48
    ld (screen+21),a
    ld a,(wave)
    and 15
    cp 10
    jp c,wave_digit
    add a,7
wave_digit:
    add a,48
    ld (screen+30),a
    ld hl,shield
    ld de,screen+704
    ld bc,64
    ldir
    ; Scan compact flags and draw only live aliens. Coordinates in B/C.
    xor a
    ld (launchy),a
    ld (rowindex),a
    ld hl,aliens
    ld (flagptr),hl
    ld a,(ay)
    ld (rowy),a
row_loop:
    ld a,(ax)
    ld (colx),a
    ld a,8
    ld (colleft),a
alien_loop:
    ld hl,(flagptr)
    ld a,(hl)
    or a
    jp z,next_alien
    ld a,(shoty)
    ld b,a
    ld a,(rowy)
    cp b
    jp nz,draw_alien
    ld a,(colx)
    ld b,a
    ld a,(shotx)
    sub b
    cp 2
    jp nc,draw_alien
    ld (hl),0
    xor a
    ld (shoty),a
    ld hl,alive
    dec (hl)
    ld a,2
    ld (effect),a
    call score_add
    jp next_alien
draw_alien:
    ld a,(rowy)
    ld b,a
    ld a,(colx)
    ld c,a
    call cell
    ld a,(direction)
    or a
    jp z,sprite_left
    ld (hl),157
    inc hl
    ld (hl),174
    jp launch_candidate
sprite_left:
    ld (hl),151
    inc hl
    ld (hl),186
launch_candidate:
    ; Prefer a live alien to the left of (or directly above) the player;
    ; keep first live alien as fallback if all are to the right.
    ld a,(launchy)
    or a
    jp z,save_launch
    ld a,(px)
    cp c
    jp c,next_alien
save_launch:
    ld a,b
    ld (launchy),a
    ld a,c
    ld (launchx),a
next_alien:
    ld hl,(flagptr)
    inc hl
    ld (flagptr),hl
    ld a,(colx)
    add a,6
    ld (colx),a
    ld hl,colleft
    dec (hl)
    jp nz,alien_loop
    ld hl,rowy
    inc (hl)
    inc (hl)
    ld hl,rowindex
    inc (hl)
    ld a,(hl)
    cp 3
    jp nz,row_loop
    ld a,(shoty)
    or a
    jp z,render_bomb
    ld b,a
    ld a,(shotx)
    ld c,a
    call cell
    ld (hl),149
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
    ld (hl),181
    inc hl
    ld (hl),176
render_floor:
    ld hl,screen+960
    ld b,64
floor_loop:
    ld (hl),140
    inc hl
    djnz floor_loop
    jp present
score_add:
    ld hl,score+2
    ld b,3
score_carry:
    inc (hl)
    ld a,(hl)
    cp 58
    ret c
    ld (hl),48
    dec hl
    djnz score_carry
    ret
; Cassette effects: short square-wave sweeps, no long delay loops.
; Interrupts stay enabled; pitch is approximate. 8-18 cycles per effect.
effect_play:
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
; 12 bytes per beat, separate note-offs and note-ons for two split voices.
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
music_tick:
    ld a,(midi)
    or a
    ret z
    ld a,(musicwait)
    or a
    jp z,music_due
    dec a
    ld (musicwait),a
    ret nz
music_due:
    ld a,(qcount)
    or a
    ret nz
    ld a,(musicrate)
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
    ld a,12
    ld (qcount),a
    ret
; Drain pending data and send pedal off + All Notes Off on exit.
; Bounded polling; no serial hardware cannot trap the game.
midi_stop:
    ld a,(midi)
    or a
    ret z
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
gameover:
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
    ld de,screen+480
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
title: db "S T A R   S I E G E",0
help1: db "LEFT / RIGHT = MOVE   SPACE = FIRE",0
help2: db "2 = 25 HZ   3 = 30 HZ   THEN SELECT",0
help3: db "ENTER = MIDI + FX   CLEAR = FX ONLY",0
help4: db "BREAK = QUIT   DESTROY THE INVADERS",0
hud: db "SCORE:0000   LIVES: 0   WAVE:0",0
overmsg: db "G A M E   O V E R",0
scoremsg: db "FINAL SCORE:",0
againmsg: db "ENTER = MENU       BREAK = EXIT",0
; Original two-part ostinato; program 71 = Electric Bass + Brass.
bassline: db 36,36,43,36,39,39,46,39,41,41,48,41,38,38,45,38
leadline: db 67,72,70,74,70,75,74,77,72,77,75,79,69,74,72,67
setup_midi: db 176,64,0,176,66,0,176,67,0,176,123,0,192,71
cleanup_midi: db 128,0,0,128,0,0,176,64,0,176,66,0,176,67,0,176,123,0
savedsp: dw 0
midi: db 0
musicrate: db 6
musicwait: db 0
musicindex: db 0
oldbass: db 0
oldupper: db 0
qcount: db 0
qpos: db 0
lasttick: db 0
lives: db 3
wave: db 1
score: db 48,48,48,48
px: db 0
shotx: db 0
shoty: db 0
fireheld: db 0
ax: db 0
ay: db 0
direction: db 0
alienwait: db 0
alive: db 0
bombx: db 0
bomby: db 0
bombwait: db 0
bombphase: db 0
launchx: db 0
launchy: db 0
cooldown: db 0
effect: db 0
rowindex: db 0
rowy: db 0
colx: db 0
colleft: db 0
flagptr: dw 0
queue: ds 18
aliens: ds 24
shield: ds 64
screen: ds 1024
stack: ds 128
stacktop:
