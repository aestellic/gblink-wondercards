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
    beq _9
    adr r3, IsWaiting
    bx r3

    .align 2
_9:
    b 9f

    .arm
    .align 2
IsWaiting:                            @to understand code properly, it might be better to start reading at CheckSave. IsWaiting, ClearWait, & EqualPreviousSave rely on code from it as they wait for a success state.      
    push {r0-r7}                      @preserve gp registers
	mov r2, #255                    @If my vblankintr is running during a save, game will crash. 
	add r2, #10                       @IsWaiting is checking if a value in r_unused is 0.
	ldr r1, r_unused                 @if it's not, it increments it by 1 until we reach 265. This is about how long the game takes to save.
	ldr r0, [r1]                      
	cmp r0, #0                        @if the value here is 0, we go to the code that checks if we're currently saving. 
	beq CheckSave
	add r0, #1                       
	cmp r0, r2
	beq ClearWait                     @if the value is 265, we clear r_unused to 0 in ClearWait. This will end the timer. 
	str r0, [r1]
	b ExitToVblankIntr                @if the timer is above 0, but under 265, we immediately exit to regular vblankintr function.

    .align 2
ClearWait:
	mov r0, #0                        @this ends waiting timer. 
	str r0, [r1]                      @if r_unused_battlers_arr contains 1, a save happened and we run EqualPreviousSave
	ldr r1, r_unused_battlers_arr
	ldr r0, [r1]
	cmp r0, #1
	bne CheckSave

    .align 2
EqualPreviousSave:                    @when wait timer ends, we have to re-set some values to make the loop work again.
	mov r0, #0                        @remove save check so can save again.
	str r0, [r1]
	mov r0, #30

    .align 2
CheckSave:
    @Main Loop to check if saving.
    ldr r0, r_save_dialog_cb          @to check if we're saving, I see if SAVE_DIALOG_CALLBACK is SAVE_DIALOG_NOW_SAVING_TEXT, which is for the NOW SAVING... text.
    bic r0, r0, #1
    ldr r0, [r0]
    bic r0, r0, #1

    ldr r1, r_save_dialog_now_saving
    bic r1, r1, #1

    cmp r0, r1
    bne ExitToVblankIntr              @if SAVE_DIALOG_CALLBACK is not equal to SAVE_DIALOG_NOW_SAVING_TEXT, exit to normal vblankintr.

    .align 2
ModifyObjEvent:
    ldr r0, r_unused                  @if not equal, hijack. 
	mov r1, #1                        @Once success state is triggered, place 1 into sUnused for IsWaiting to begin its loop of 265 frames. 
	str r1, [r0]
	ldr r0, r_unused_battlers_arr     @set this to 1. If it's 1, EqualPreviousSave will trigger. 
	str r1, [r0]

    @ setup object event here
    @@ ObjectEvent @@
    mov r0, #0x1
    ldr r3, r_get_objevent_by_id
    orr r3, r3, #1
    mov lr, pc
    bx r3                               @ i = GetObjectEventIdByLocalId(0x1)

    lsl r1, r0, #0x5                    @ r1 = i * 32
    lsl r0, r0, #0x2                    @ r0 = i * 4
    add r3, r0, r1                      @ r3 = r0 + r1 = i * 36

    ldr r0, r_sb1_ptr
    ldr r0, [r0]

    ldrh r1, [r0]                       @ r1 = gSaveBlock1Ptr->pos.x
    ldrh r2, [r0, #0x2]                 @ r2 = gSaveBlock1Ptr->pos.y
    
    @mov r12, #0x6A
    @lsl r12, r12, #0x4                  @ 0x6A0
    @add r0, r0, r12                     @ r0 = gSaveBlock1Ptr->objectEvents
    ldr r0, r_obj_events
    add r0, r0, r3                      @ r0 = gObjectEvents[i]
    add r0, r0, #0x10                   @ r0 = gObjectEvents[i].currentCoords.x

    strh r1, [r0]                       @ gObjectEvents[i].currentCoords.x = gSaveBlock1Ptr->pos.x
    sub r2, r2, #1
    strh r2, [r0, #2]                   @ gObjectEvents[i].currentCoords.y = gSaveBlock1Ptr->pos.y - 1

    @@ ObjectEventTemplate @@
    sub r0, r0, #0x10                   @ r0 = gObjectEvents[i]
    ldr r3, r_get_objevent_base_template
    push {r1-r2}
    mov lr, pc
    bx r3                               @ j = GetBaseTemplateForObjectEvent(gObjectEvents[i])
    pop {r1-r2}

    strh r1, [r0, #0x04]                @ gSaveBlock1Ptr->objectEventTemplates[j].x = gSaveBlock1Ptr->pos.x
    strh r2, [r0, #0x06]                @ gSaveBlock1Ptr->objectEventTemplates[j].y = gSaveBlock1Ptr->pos.y - 1

    mov r1, #0x02
    strh r1, [r0, #0x0C]                @ gSaveBlock1Ptr->objectEventTemplates[j].trainerType = TRAINER_TYPE_SEE_ALL_DIRECTIONS

    ldr r1, r_example_script
    str r1, [r0, #0x10]                 @ gSaveBlock1Ptr->objectEventTemplates[j].script = EXAMPLE_SCRIPT
    
    .align 2
ExitToVblankIntr:
    pop {r0-r7}
    adr r3, 9f
    orr r3, r3, #1
    bx r3

    .thumb
    .align 2
9:
    ldr r3, [r4, #KEPT]
    bl r_call_r3
    pop {r4, r7}
    pop {r0}
    bx r0

r_call_r3:
    bx r3

    .align 2

r_state:                        .word STATE
r_main:                         .word MAIN
.if EMERALD
r_map_header:                   .word MAP_HEADER
.else
r_help_r_disable:               .word HELP_R_DISABLE
r_quest_log_state:              .word QUEST_LOG_STATE
.endif
r_save_dialog_cb:               .word SAVE_DIALOG_CALLBACK
r_save_dialog_now_saving:       .word SAVE_DIALOG_NOW_SAVING_TEXT
r_sb1_ptr:                      .word SB1_PTR
r_cb1_overworld:                .word CB1_OVERWORLD
r_cb2_overworld:                .word CB2_OVERWORLD
r_controls_locked:              .word CONTROLS_LOCKED
r_script_status:                .word SCRIPT_STATUS
r_player_avatar:                .word PLAYER_AVATAR
r_in_union_room:                .word IN_UNION_ROOM
r_setup_script:                 .word SETUP_SCRIPT
r_unused_battlers_arr:          .word UNUSED_BATTLERS_ARRAY
r_unused:                       .word S_UNUSED
r_intr_main_buffer:             .word INTR_MAIN_BUFFER
r_get_objevent_by_id:           .word GET_OBJEVENT_BY_ID
r_get_objevent_base_template:   .word GET_OBJEVENT_BASE_TEMPLATE
r_example_script:               .word EXAMPLE_SCRIPT
r_obj_events:                   .word OBJECT_EVENTS

    .align 2
resident_end:
