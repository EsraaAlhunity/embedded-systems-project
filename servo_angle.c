#include <xc.h>

/*  Configuration  */
#pragma config FOSC = HS
#pragma config WDTE = OFF
#pragma config PWRTE = ON
#pragma config BOREN = ON
#pragma config LVP = OFF
#pragma config CPD = OFF
#pragma config WRT = OFF
#pragma config CP = OFF

#define _XTAL_FREQ 500000

/*  Variables */
volatile unsigned char angle = 0;
volatile unsigned char duty_cycle = 0;
volatile unsigned char flag = 0;

volatile unsigned char digit_index = 0;
volatile unsigned char digit1 = 0;
volatile unsigned char digit2 = 0;
volatile unsigned char digit3 = 0;
volatile unsigned char digit4 = 0;

/*  Function Prototypes  */
void init(void);
char readKeypad(void);
unsigned char ConvertAngle(void);
void split_digit(void);
void multiplexing(void);
unsigned char seg_table(unsigned char num);

/*  Interrupt  */
void __interrupt() ISR(void)
{
    if (INTCONbits.INTF)
    {
        flag ^= 1;
        INTCONbits.INTF = 0;

        if (flag)
            CCPR1L = 31;       // brake
        else
            CCPR1L = ConvertAngle();
    }

    if (PIR1bits.TMR2IF)
        PIR1bits.TMR2IF = 0;
}

/* Initialization  */
void init(void)
{
    TRISB = 0b11110001;
    TRISC = 0b11100000;
    TRISD = 0b10000000;

    CCP1CON = 0b00001100;
    T2CON   = 0b00000111;
    PR2     = 155;

    PIE1bits.TMR2IE = 1;
    PIR1bits.TMR2IF = 0;

    INTCONbits.PEIE = 1;
    INTCONbits.INTE = 1;
    INTCONbits.GIE  = 1;
    INTCONbits.INTF = 0;

    PORTB = 0xFF;
    PORTC = 0x00;
    PORTD = 0x00;
}

/* Keypad */
char readKeypad(void)
{
    const char table[12] = {
        '1','2','3',
        '4','5','6',
        '7','8','9',
        '*','0','#'
    };

    for (unsigned char col = 0; col < 3; col++)
    {
        PORTB = ~(1 << (col + 1));
        __delay_ms(5);

        if (!RB4) return table[0*3 + col];
        if (!RB5) return table[1*3 + col];
        if (!RB6) return table[2*3 + col];
        if (!RB7) return table[3*3 + col];
    }
    return 0;
}

/*  Convert angle value to PWM duty cycle  */
unsigned char ConvertAngle(void)
{
    return (angle / 6) + 31;
}

/*  Split digits  */
void split_digit(void)
{
    digit1 = angle / 100;
    digit2 = (angle % 100) / 10;
    digit3 = angle % 10;
    digit4 = 0;
}

/*  7-Seg  */
unsigned char seg_table(unsigned char num)
{
    const unsigned char seg[10] = {
        0x3F,0x06,0x5B,0x4F,0x66,
        0x6D,0x7D,0x07,0x7F,0x6F
    };
    return seg[num];
}

/*  Miltiplexer */
void multiplexing(void)
{
    for (digit_index = 0; digit_index < 4; digit_index++)
    {
        PORTC = 0;

        if (digit_index == 0) PORTCbits.RC0 = 1;
        if (digit_index == 1) PORTCbits.RC1 = 1;
        if (digit_index == 2) PORTCbits.RC3 = 1;
        if (digit_index == 3) PORTCbits.RC4 = 1;

        if (digit_index == 0) PORTD = seg_table(digit1);
        if (digit_index == 1) PORTD = seg_table(digit2);
        if (digit_index == 2) PORTD = seg_table(digit3);
        if (digit_index == 3) PORTD = seg_table(digit4);

        __delay_ms(2);
    }
}

/*  Main  */
void main(void)
{
    char key;
    init();

    while (1)
    {
        digit_index = 0;
        digit1 = digit2 = digit3 = 0;

/* ====== Enter 3 digits ====== */
        while (digit_index < 3)
        {
            key = readKeypad();
            if (!key) continue;

            if (key >= '0' && key <= '9')
            {
                if (digit_index == 0) digit1 = key - '0';
                if (digit_index == 1) digit2 = key - '0';
                if (digit_index == 2) digit3 = key - '0';
                digit_index++;
            }
        }
/*  Wait for # or *  */
        while (1)
        {
            key = readKeypad();
            if (!key) continue;

            if (key == '*') continue;

            if (key == '#')
            {
                if (digit_index > 0)
                {
                    digit_index--;
                    if (digit_index == 2) digit3 = 0;
                    if (digit_index == 1) digit2 = 0;
                    if (digit_index == 0) digit1 = 0;
                }
                break;
            }
        }

        angle = digit1 * 100 + digit2 * 10 + digit3;

        CCPR1L = ConvertAngle();
        split_digit();
        multiplexing();
    }
}
