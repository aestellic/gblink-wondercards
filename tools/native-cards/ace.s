@modify ObjectEventTemplate[1]
@    trainerType = TRAINER_TYPE_SEE_ALL_DIRECTIONS (0x2)
@    active = true
@    script = whatever u want
@    movementType = MOVEMENT_TYPE_FACE_DOWN (0x8)
@    x = player's x
@    y = player's y+1

    .syntax unified
    .thumb
    .text
    .align 2

    .equ RESIDENT, 0x0203FC00           @ unused RAM in both games
    .equ ENABLED, 0                     @ STATE: u8
    .equ KEPT, 4                        @ the V-blank handler the hook calls
    .equ MAIN_CALLBACK1, 0
    .equ MAIN_CALLBACK2, 4
    .equ MAIN_INTR_CHECK, 0x1C
    .equ MAIN_NEW_KEYS, 0x2E
    .equ BUTTON_R_BIT, 8
    .equ TILE_TRANSITION_STATE, 3       @ in gPlayerAvatar: 0 while standing still
    .equ CONTEXT_SHUTDOWN, 2
    .equ MAP_SECTION, 0x14              @ in gMapHeader
    .equ MAPSEC_BATTLE_FRONTIER, 0x3A
    .equ QL_STATE_PLAYBACK, 2           @ and 3, its last scene
    .equ SE_PC_LOGIN, 2
    .equ IME, 0x04000208

install:
    push {r4, r5, r6, lr}
    ldr r3, p_ime
    ldrh r6, [r3]
    movs r0, #0
    strh r0, [r3]                       @ no interrupts while the hook changes
    ldr r5, p_resident
    adr r4, resident
    movs r0, #(resident_end - resident) / 4
    lsls r0, r0, #2
1:  subs r0, #4
    ldr r1, [r4, r0]
    str r1, [r5, r0]
    bne 1b
    ldr r4, p_state
    movs r0, #1
    strb r0, [r4, #ENABLED]
    ldr r0, p_intr_vblank
    ldr r1, [r0]
    subs r3, r1, r5
    lsrs r3, r3, #10
    beq 3f                              @ already installed
    str r1, [r4, #KEPT]
    adds r1, r5, #1
    str r1, [r0]
3:  ldr r3, p_ime
    strh r6, [r3]
    pop {r4, r5, r6, pc}

uninstall:
    ldr r0, p_state
    movs r1, #0
    strb r1, [r0, #ENABLED]
.if EMERALD == 0
    ldr r0, p_help_r_disable
    strb r1, [r0]
.endif
    bx lr

    .align 2
.if EMERALD == 0
p_help_r_disable: .word HELP_R_DISABLE
.endif
p_ime:            .word IME
p_resident:       .word RESIDENT
p_state:          .word STATE
p_intr_vblank:    .word INTR_VBLANK

@ ---- copied to RESIDENT
    .align 2
resident:
    push {r4, r7, lr}
    ldr r4, r_state
    ldrb r0, [r4, #ENABLED]
    cmp r0, #0
    beq 9f
    ldr r7, r_main
    ldrh r0, [r7, #MAIN_INTR_CHECK]
    lsls r0, r0, #31
    bne 9f                              @ the game is mid-frame
@    ldrh r0, [r7, #MAIN_NEW_KEYS]
@    lsrs r0, r0, #BUTTON_R_BIT + 1
@    bcc 9f                              @ R not just pressed
    ldr r0, [r7, #MAIN_CALLBACK1]
    ldr r1, r_cb1_overworld
    cmp r0, r1
    bne 9f
    ldr r0, [r7, #MAIN_CALLBACK2]
    ldr r1, r_cb2_overworld
    cmp r0, r1
    bne 9f
    ldr r0, r_controls_locked
    ldrb r0, [r0]
    cmp r0, #0
    bne 9f
    ldr r0, r_script_status
    ldrb r0, [r0]
    cmp r0, #CONTEXT_SHUTDOWN
    bne 9f
    ldr r0, r_player_avatar
    ldrb r0, [r0, #TILE_TRANSITION_STATE]
    cmp r0, #0
    bne 9f
.if EMERALD
    ldr r0, r_map_header
    ldrb r0, [r0, #MAP_SECTION]
    cmp r0, #MAPSEC_BATTLE_FRONTIER
    beq 9f
.else
    ldr r0, r_quest_log_state
    ldrb r0, [r0]
    cmp r0, #QL_STATE_PLAYBACK
    bcs 9f
.endif
.arm
IsWaiting:                            @to understand code properly, it might be better to start reading at CheckSave. IsWaiting, ClearWait, & EqualPreviousSave rely on code from it as they wait for a success state.      
    push {r0-r7}                      @preserve gp registers
	mov r2, #255                    @If my vblankintr is running during a save, game will crash. 
	add r2, #10                       @IsWaiting is checking if a value in r_unused is 0.
	ldr r1, =r_unused                 @if it's not, it increments it by 1 until we reach 265. This is about how long the game takes to save.
	ldr r0, [r1]                      
	cmp r0, #0                        @if the value here is 0, we go to the code that checks if we're currently saving. 
	beq CheckSave
	add r0, #1                       
	cmp r0, r2
	beq ClearWait                     @if the value is 265, we clear r_unused to 0 in ClearWait. This will end the timer. 
	str r0, [r1]
	b ExitToVblankIntr                @if the timer is above 0, but under 265, we immediately exit to regular vblankintr function. 
ClearWait:
	mov r0, #0                        @this ends waiting timer. 
	str r0, [r1]                      @if r_unused_battlers_arr contains 1, a save happened and we run EqualPreviousSave
	ldr r1, =r_unused_battlers_arr
	ldr r0, [r1]
	cmp r0, #1
	bne CheckSave
EqualPreviousSave:                    @when wait timer ends, we have to re-set some values to make the loop work again.
	mov r0, #0                        @remove save check so can save again.
	str r0, [r1]
	mov r0, #30
CheckSave:
    @Main Loop to check if saving.
    ldr r0, =r_save_dialog_cb         @to check if we're saving, I see if SAVE_DIALOG_CALLBACK is SAVE_DIALOG_NOW_SAVING_TEXT, which is for the NOW SAVING... text.
    ldr r0, [r0]
    ldr r1, =r_save_dialog_now_saving
    cmp r0, r1
    bne ExitToVblankIntr              @if SAVE_DIALOG_CALLBACK is not equal to SAVE_DIALOG_NOW_SAVING_TEXT, exit to normal vblankintr.
ModifyObjEvent:
    ldr r0, =r_unused                 @if not equal, hijack. 
	mov r1, #1                        @Once success state is triggered, place 1 into sUnused for IsWaiting to begin its loop of 265 frames. 
	str r1, [r0]
	ldr r0, =r_unused_battlers_arr    @set this to 1. If it's 1, EqualPreviousSave will trigger. 
	str r1, [r0]

    @ setup object event here
    ldr r0, r_sb1_ptr
    ldr r0, [r0]
    ldr r1, [r0]                      @ r1 = gSaveBlock1Ptr->pos
    ldr r2, =0x8FB
    add r0, r0, r2
    str r1, [r0]                      @ gSaveBlock1Ptr->ObjectEventTemplates[1]->x = gSaveBlock1Ptr->pos.x
    add r1, r1, #1
    str r1, [r0, #1]                  @ gSaveBlock1Ptr->ObjectEventTemplates[1]->y = gSaveBlock1Ptr->pos.y + 1
ExitToVblankIntr:
    ldr r0, =r_intr_main_buffer+0x12C    @Restore proper LR VblankIntr needs.
	mov lr, r0
    pop {r0-r7}
	ldr r3, =p_intr_vblank
    .thumb
    bx r3
9:
.thumb
    ldr r3, [r4, #KEPT]
    bl r_call_r3
    pop {r4, r7}
    pop {r0}
    bx r0

r_call_r3:
    bx r3

    .align 2

r_state:                    .word STATE
r_main:                     .word MAIN
.if EMERALD
r_map_header:               .word MAP_HEADER
.else
r_help_r_disable:           .word HELP_R_DISABLE
r_quest_log_state:          .word QUEST_LOG_STATE
.endif
r_save_dialog_cb:           .word SAVE_DIALOG_CALLBACK
r_save_dialog_now_saving:   .word SAVE_DIALOG_NOW_SAVING_TEXT
r_sb1_ptr:                  .word SB1_PTR
r_cb1_overworld:            .word CB1_OVERWORLD
r_cb2_overworld:            .word CB2_OVERWORLD
r_controls_locked:          .word CONTROLS_LOCKED
r_script_status:            .word SCRIPT_STATUS
r_player_avatar:            .word PLAYER_AVATAR
r_in_union_room:            .word IN_UNION_ROOM
r_setup_script:             .word SETUP_SCRIPT
r_unused_battlers_arr:      .word UNUSED_BATTLERS_ARRAY
r_unused:                   .word S_UNUSED
r_intr_main_buffer:         .word INTR_MAIN_BUFFER

r_pc_script:       .word RESIDENT + (pc_script - resident)
pc_script:
    .byte 0x23                          @ callnative: the map name banner away
    .4byte HIDE_MAP_NAME
    .byte 0x69                          @ lockall
    .byte 0x2F, SE_PC_LOGIN, 0          @ playse
    .byte 0x25, PC_SPECIAL & 0xFF, PC_SPECIAL >> 8   @ special ShowPokemonStorageSystemPC
    .byte 0x27                          @ waitstate
    .byte 0x6B                          @ releaseall
    .byte 0x02                          @ end
    .align 2
resident_end:

@gObjectEvents[1].active = 0x1
@    0x02037350 + 0x25 = 0x1
@gObjectEvents[1].trainerType = 0x2
@    0x02037350 + 0x25 + 0x7 = 0x2
@gObjectEvents[1].script = 0x082725f2
@    0x02037350 + 0x25 + 0x7 = 0x2
@gObjectEvents[1].movementType = 0x8
@
