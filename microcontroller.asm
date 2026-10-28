#include <p16f877a.inc>
	
ORG 0x00
    GOTO start

ORG 0x04
    GOTO ISR
;----------------------
; VARIABLES 
;----------------------
CBLOCK 0x20
    angle       
    duty_cycle        
    tempW
    tempSTATUS
    ROW_INDEX
    COL_INDEX
    index
    flag
    digit_index      
    digit1
    digit2
    digit3
	digit4     
endc
;----------------------
; INITIALIZATION
;----------------------
start:
; Configure TRIS Registers
    banksel TRISB
    movlw b'11110001'     
    movwf TRISB
    
    banksel TRISD
    movlw b'10000000'
    movwf TRISD

    banksel TRISC
    movlw b'11100000'     
    movwf TRISC
    
; Configure Timer2 for PWM
    banksel CCP1CON
    movlw b'00001100'     ; Set CCP1 to PWM mode
    movwf CCP1CON
    
    banksel T2CON
    movlw b'00000111'     ; Timer2 ON, prescaler 1:16
    movwf T2CON
;----------------------
;PWM Period
;tpwm = (PR2+1)*4*prescaler*Tosc ---->20ms/50HZ 
; PR2 = 155 for ~50Hz PWM (based on Fosc=500KHZ and prescaler=16)Tosc=2Ms=0.002ms
;----------------------
    banksel PR2
    movlw d'155'           
    movwf PR2
;----------------------   
; Enable Interrupts
;----------------------
    banksel PIE1
    bsf PIE1, TMR2IE      
	bcf PIR1, TMR2IF
    banksel INTCON
    bsf INTCON, PEIE      
    bsf INTCON, INTE      
    bsf INTCON, GIE       
	bcf INTCON, INTF
;----------------------   
; Clear Ports and Flags
;----------------------
    banksel flag
    clrf flag  
    banksel PORTD
    clrf PORTD
    banksel PORTC
    clrf PORTC
    banksel PORTB
    movlw b'11111111' 
    movwf PORTB
;---------------------------
; step to enter into keypad
;---------------------------	
loop:
    movf flag, W
    btfsc STATUS, Z
  	goto loop2
    goto loop
loop2:
	clrf digit_index ; = 0
    call readkeypad
    movwf digit1
    incf digit_index, F ; = 1
    call readkeypad
    movwf digit2
    incf digit_index, F ; = 2
    call readkeypad
    movwf digit3
    incf digit_index, F ; = 3
  
loop3:
    call readkeypad
    movwf index
    movf index, W
    sublw '*'
    btfsc STATUS, Z
    goto loop3
    movf index, W
    sublw '#'
    btfss STATUS, Z
    goto loop3
;----------------------    
; BACKSPACE 
;----------------------
    movf digit_index, W
    btfsc STATUS, Z
    goto loop2  
     
    movlw 3
    subwf digit_index, W
    btfsc STATUS, Z
    goto clear_d3
    
    movlw 2
    subwf digit_index, W
    btfsc STATUS, Z
    goto clear_d2

    movlw 1
    subwf digit_index, W
    btfsc STATUS, Z
    goto clear_d1

clear_d3:
    clrf digit3
    decf digit_index, F
    goto loop3

clear_d2:
    clrf digit2
    decf digit_index, F
    goto loop3

clear_d1:
    clrf digit1
    decf digit_index, F
    goto loop2 
;----------------------------------------- 
; this to rest the angle as real num .
;converts ASCII to number 
;-----------------------------------------
    movf digit1, W
    sublw '0'     
    movwf digit1

    movf digit2, W
    sublw '0'
    movwf digit2

    movf digit3, W
    sublw '0'
    movwf digit3
;------------------------------------------
 ; angle = digit1*100 + digit2*10 + digit3
 ; digit1 * 100
 ;-----------------------------------------
	clrf angle
	movf digit1, W
	movwf tempW
    movlw D'100'
    movwf tempSTATUS

mul1:
    addwf angle, F
    decfsz tempSTATUS, F
    goto mul1
;----------------------
; digit2 * 10
;----------------------
    movf digit2, W
	movwf tempW
	movlw D'10'
	movwf tempSTATUS

mul2:
    addwf angle, F
    decfsz tempSTATUS, F
    goto mul2
;----------------------
; digit3
;----------------------
    movf digit3, W
    addwf angle, F

    call ConvertAngle
    movwf CCPR1L
    call split_digit
    call multiplexing
    goto loop
;#########################
;----------------------
;the ISR code
;----------------------
ISR:
    movwf tempW
    movf STATUS, W
    movwf tempSTATUS
; External INT RB0
    btfsc INTCON, INTF
    goto brakestate
; Clear Timer2 IF
    btfsc PIR1, TMR2IF
    bcf PIR1, TMR2IF
    goto restore_ISR

brakestate:
    movf flag, W
    xorlw 0x01
    movwf flag
    bcf INTCON, INTF
	btfsc flag, 0       
	goto do_brake
    goto do_resume
  do_brake:
    movlw d'31' 
 	movwf CCPR1L  
	goto restore_ISR
do_resume:
	call ConvertAngle
	movwf CCPR1L
	goto restore_ISR
restore_ISR:
    movf tempSTATUS, W
    movwf STATUS
    movf tempW, W
    RETFIE
;----------------------------
; READ KEYPAD 4x3
; Columns: RB1 RB3 (output)
; Rows: RB4 RB7 (input)
;----------------------------
readkeypad:
   clrf ROW_INDEX
   clrf COL_INDEX
READ_COL:
    movlw B'11111101' ; RB1 LOW
    movwf PORTB
    movlw 0
    movwf COL_INDEX
    call FIND_ROW
    btfss STATUS, Z
    goto FOUND_KEY
    movlw B'11111011' ; RB2 LOW ;ENABLE 
    movwf PORTB
    movlw 1           ;STORE THE NUM OF THE COLUMN 
    movwf COL_INDEX
    call FIND_ROW
    btfss STATUS, Z
    goto FOUND_KEY
    movlw B'11110111' ; RB3 LOW
    movwf PORTB
    movlw 2
    movwf COL_INDEX
    call FIND_ROW
    btfss STATUS, Z
    goto FOUND_KEY
    clrw            
    RETURN
;------------------------------------------
; Use (ROW_INDEX * 3 + COL_INDEX) ? index
; Convert index to number
;------------------------------------------
FOUND_KEY:
    movf ROW_INDEX,  W
    addwf ROW_INDEX, W
    addwf ROW_INDEX, W     ; W = 3 * row
    addwf COL_INDEX, W     ; + col
    movwf index
    movf index, W
    addwf PCL, F        ;go to keypad table
;----------------------
; Key LOOKUP TABLE
;---------------------- 
; Returns the ASCII for the input of the keypad   
keypadtable:
    retlw 0x31  ; '1'
    retlw 0x32   ; '2'
    retlw 0x33   ; '3'
    retlw 0x34   ; '4'
    retlw 0x35   ; '5'
    retlw 0x36   ; '6'
    retlw 0x37   ; '7'
    retlw 0x38   ; '8'
    retlw 0x39   ; '9'
    retlw 0x2A   ; '*'  
    retlw 0x30   ; '0'
    retlw 0x23   ; '#'  

;----------------------    
; Check RB4 RB7 for LOW
;----------------------
FIND_ROW:
    btfss PORTB, 4
    movlw 0
    movwf ROW_INDEX
    RETURN
    btfss PORTB, 5
    movlw 1
    movwf ROW_INDEX
    RETURN
    btfss PORTB, 6
    movlw 2
    movwf ROW_INDEX
    RETURN
    btfss PORTB, 7
    movlw 3
    movwf ROW_INDEX
    RETURN
    clrw   ;RETURN 0 IF DOESNT PRESS ANY NUM 
    RETURN
;----------------------------
;convert ANGLE TO DUTY (Linear map)
;duty = (angle  / 6 )+ 31
;----------------------------
ConvertAngle:
    movf angle, W
    movwf tempW
  clrf duty_cycle
      DIV_BY_6:
    movlw D'6'
    subwf tempW, F
    btfss STATUS, C    
    goto DIV_LOOP
    incf duty_cycle, F
    goto DIV_BY_6
DIV_LOOP:
  	movf duty_cycle, W
  	addlw D'31'
    RETURN
;#########################
;--------------------------
; split  digit for display
;--------------------------
; angle (0-->180) ? digit1,2,3
split_digit:
    movf angle, W
    movwf tempW
    clrf digit1 

    movlw d'100'
    call division
    movwf digit2       ; hundreds

    movlw d'10'
    call division
    movwf digit3       ; tens

    movf tempW, W
    movwf digit4       ; units
    RETURN

division:
    clrf digit_index
division2:
    subwf tempW, F
    btfss STATUS, C
    goto div_done
    incf digit_index, F
    goto division2
div_done:
    movf digit_index, W
    RETURN
;----------------------
; display multiplex
;----------------------
multiplexing:
    clrf digit_index
display:
    movf digit_index, W
    call select
    call lookup_table
    movwf PORTD
    call delay
    incf digit_index, F
    movf digit_index, W
    sublw D'4'   
    btfss STATUS, Z
    goto display
    RETURN

select:
    bcf PORTC, 0
    bcf PORTC, 1
    bcf PORTC, 3
	bcf PORTC, 4

    movf digit_index, W
    addwf PCL, F

sel0: bsf PORTC, 0
      RETURN
sel1: bsf PORTC, 1
      RETURN
sel2: bsf PORTC, 3
      RETURN
sel3: bsf PORTC, 4
	  RETURN
;----------------------
;the lookup table
;----------------------
lookup_table:
    movf digit_index, W
    addwf PCL, F
    goto d1
    goto d2
    goto d3
 	goto d4


d1: movf digit1, W
        call seg_table
        RETURN

d2: movf digit2, W
        call seg_table
        RETURN

d3: movf digit3, W
        call seg_table
        RETURN

d4: movf digit4, W 
 		call seg_table
		RETURN
;----------------------
; 7 SEGMENT TABLE 
;----------------------
seg_table:
    addwf PCL, F
    retlw b'00111111' ; 0
    retlw b'00000110' ; 1
    retlw b'01011011' ; 2
    retlw b'01001111' ; 3
    retlw b'01100110' ; 4
    retlw b'01101101' ; 5
    retlw b'01111101' ; 6
    retlw b'00000111' ; 7
    retlw b'01111111' ; 8
    retlw b'01101111' ; 9
;----------------------
;delay code 
;----------------------
delay:
    movlw d'250'
    movwf tempW
d_loop:
    decfsz tempW, F
    goto d_loop
    RETURN

    END