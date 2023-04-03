#include <at89c5131.h>

USING 0x00

ORG 2000h
	JMP    INICIO

ORG 200Bh
	JMP    TIMER0_IRQ
	
ORG 2100h
;-----------------------------------------------------------------------------------------
;	LCD
;-----------------------------------------------------------------------------------------
RS		EQU	P2.5			;COMANDO RS LCD
E_LCD	EQU	P2.7			;COMANDO E (ENABLE) LCD
RW		EQU	P2.6			;READ/WRITE
BUSYF	EQU	P0.7			;BUSY FLAG
;-----------------------------------------------------------------------------------------
;	Tabela de strings
;-----------------------------------------------------------------------------------------
STR_S51:
		DB		'   SOUSVIDE51   ',00H	
STR_CLR:
		DB      '                ',00H		
;-----------------------------------------------------------------------------------------
;	Tabela de Alimentos
;-----------------------------------------------------------------------------------------
STR_CARNE:
		DB      ' CARNE    		 ',00H
STR_PEIXE:
		DB  	' PEIXE    		 ',00H
STR_FRANGO:
		DB  	' FRANGO   		 ',00H
STR_TESTE:
		DB  	' TESTE    		 ',00H			
STR_CARNE_MP:
		DB      ' MAL PASSADO 	 ',00H
STR_CARNE_AP:
		DB      ' AO PONTO   	 ',00H
STR_CARNE_BP:
		DB      ' BEM PASSADO  	 ',00H
;-----------------------------------------------------------------------------------------
;	Tabelas de tempo
;-----------------------------------------------------------------------------------------	
TABELA_TEMPO:
	TEMPO_CARNE: 	DB 60,60,60
	TEMPO_PEIXE: 	DB 40,40,45
	TEMPO_FRANGO: 	DB 60,60,60
	TEMPO_TESTE: 	DB 1,10,15		
;-----------------------------------------------------------------------------------------
;	Tabelas de temperatura - mal passado, ao ponto e bem passado
;-----------------------------------------------------------------------------------------
TABELA_TEMPERATURA:
	TEMPERATURA_CARNE: 	DB 087h,091h,0A2h  ; temperatura x2.5 em hexa => cada ponto no adc = 0.04 graus
	TEMPERATURA_PEIXE: 	DB 064h,07Dh,096h
	TEMPERATURA_FRANGO: DB 096h,0A2h,0BBh
	TEMPERATURA_TESTE: 	DB 04Bh,064h,096h
;-----------------------------------------------------------------------------------------
;	Definiçao do RTC
;-----------------------------------------------------------------------------------------
CRYSTAL         EQU 24000000            ;FREQ crystal
TMRCYCLE        EQU 12                  ;ciclos de maquina -pulsos do cristal
TMR_SEC	        EQU CRYSTAL/TMRCYCLE    ;The # of timer increments per second = 2000000
QUANTA			EQU 40
FTH_DE_SEGUNDO  EQU TMR_SEC/QUANTA     	; valor de qnts incrementos acontecem em .05 seg = 100000
RESET_VALUE     EQU 15536  	
;-----------------------------------------------------------------------------------------
;	Definiçao do número de alimentos
;-----------------------------------------------------------------------------------------
NUM_ALIMENTO 	EQU 4
;-----------------------------------------------------------------------------------------
;	Definição dos botoes
;-----------------------------------------------------------------------------------------   
SW_DOWN			EQU		P3.4	
SW_ENTER		EQU		P3.2
;-----------------------------------------------------------------------------------------
;	Definição dos LEDs
;-----------------------------------------------------------------------------------------
LEDVD			EQU		P3.6
LEDAM   		EQU		P3.7
LEDVM			EQU		P1.4
;-----------------------------------------------------------------------------------------
;	Definição dos pinos do ADC
;-----------------------------------------------------------------------------------------
SPI_MISO		EQU 	P1.5
SPI_MOSI		EQU		P1.7 
SPI_CLK			EQU		P1.6
SPI_ADC_CS		EQU		P1.1
;-----------------------------------------------------------------------------------------
;	Definição de variáveis utilizadas pela função ADC
;-----------------------------------------------------------------------------------------
ADC_V_RAW		EQU		30h
TEMP_ADC_MSB	EQU		31h
TEMP_ADC_LSB 	EQU		32h
;-----------------------------------------------------------------------------------------
;	Definição do controle do relé
;-----------------------------------------------------------------------------------------
RELE_CONTROL 	EQU		P2.0
;-----------------------------------------------------------------------------------------
;	VARIAVEIS
;-----------------------------------------------------------------------------------------
ALIMENTO_ATUAL 		EQU 40h
PONTO_ATUAL 		EQU 41h
TEMPERATURA_ALVO 	EQU 42h
TEMPO_ALVO			EQU 43h
SEGUNDOS			EQU 44h
MINUTOS				EQU 45h
HORAS				EQU 46h
TICKS 				EQU 47h
STR_TEMP			EQU 48h ; vai de 48h a 58h
STR_HRS				EQU 50h	; str hrs
STR_2P0				EQU 52h
STR_MIN				EQU 53h	; str min
STR_2P1				EQU 55h
STR_SEG				EQU 56h	; str seg
FLAG				EQU	57h
NOVO_SEGUNDO		EQU 59h
;-----------------------------------------------------------------------------------------
;	INICIO DO PROGRAMA
;-----------------------------------------------------------------------------------------
INICIO:
	CALL   INIDISP
	MOV    DPTR,#STR_S51
	CALL   ESC_STR1
	MOV	   DPTR,#STR_CARNE	
	CALL   ESC_STR2
	CALL   INICIALIZAR_VARIAVEIS
	
;-----------------------------------------------------------------------------------------
;	Rotina do menu - seleção do alimento
;-----------------------------------------------------------------------------------------
LOOP_ALIMENTOS:
	
	CALL CHECK_DOWN
	JNZ CHAMA_PROXIMO_ALIMENTO
	CALL CHECK_ENTER
	JNZ LOOP_INICIO_PONTO
	JMP LOOP_ALIMENTOS
	
	CHAMA_PROXIMO_ALIMENTO:
	CALL PROXIMO_ALIMENTO
	JMP LOOP_ALIMENTOS

LOOP_INICIO_PONTO:
	JNB SW_ENTER, LOOP_INICIO_PONTO
	MOV DPTR,#STR_CARNE_MP
	CALL ESC_STR2
;-----------------------------------------------------------------------------------------
;	Rotina do menu - seleção do ponto
;-----------------------------------------------------------------------------------------
LOOP_PONTO:
	CALL CHECK_DOWN
	JNZ CHAMA_PROXIMO_PONTO
	CALL CHECK_ENTER
	JNZ PEGA_TEMPO_TEMPERATURA
	JMP LOOP_PONTO
	
	CHAMA_PROXIMO_PONTO:
	CALL PROXIMO_PONTO
	JMP LOOP_PONTO

PEGA_TEMPO_TEMPERATURA:
	MOV A,ALIMENTO_ATUAL
	MOV B,#3
	MUL AB
	ADD A,PONTO_ATUAL
	PUSH ACC
	MOV DPTR,#TABELA_TEMPERATURA
	MOVC A,@A+DPTR
	MOV TEMPERATURA_ALVO,A
	POP ACC
	MOV DPTR,#TABELA_TEMPO
	MOVC A,@A+DPTR
	MOV TEMPO_ALVO,A

	JMP INICIAR_OPERACAO
;-----------------------------------------------------------------------------------------
;	Rotina principal - pega os valores escolhidos no menu, inicia o timer, 
;  					   monitora a temperatura e liga o rabo quente				
;-----------------------------------------------------------------------------------------
INICIAR_OPERACAO:
	CLR LEDAM
	MOV 	DPTR,#STR_CLR
	CALL 	ESC_STR1
	MOV MINUTOS,TEMPO_ALVO
	MOV NOVO_SEGUNDO,#1
	CALL INICIAR_RTC ;-> inicializa o timer

	ESCREVE:
	; SINCRONIA DE ESCRITA
	MOV R0,#NOVO_SEGUNDO
	CJNE @R0,#1,NAO_ESCREVE
	MOV NOVO_SEGUNDO,#0
	CALL ATUALIZA_STR_TEMP
	CALL CLR2L
	MOV DPTR,#STR_TEMP
	CALL MSTRINGX	
	
	NAO_ESCREVE:		
	CALL 	LEITURA_ADC
	CALL 	CALC_TEMPERATURA
	CALL  	TEMPERATURA_LCD
	CJNE	R6,#0,CONTROLE_TEMPERATURA_SUBINDO
	CJNE	R7,#0,CONTROLE_TEMPERATURA_DESCENDO
	CALL	CONTROLE_TEMPERATURA 
	
	JMP ESCREVE
;-----------------------------------------------------------------------------------------
;	Rotina que calcula o valor da temperatura baseado na entrada do ADC
;-----------------------------------------------------------------------------------------
CALC_TEMPERATURA:
	PUSH	ACC

	MOV		A,	ADC_V_RAW
	MOV		DPTR,	#TABLE_LM35_LOW_TO_BCD
	MOVC	A,	@A+DPTR
	MOV		TEMP_ADC_LSB,	A
	
	MOV		A,	ADC_V_RAW
	MOV		DPTR,	#TABLE_LM35_HIGH_TO_BCD
	MOVC	A,	@A+DPTR
	MOV		TEMP_ADC_MSB,	A

	POP		ACC
	RET
;-----------------------------------------------------------------------------------------
;	Rotina que liga e desliga o rabo quente baseado na temperatura 
;-----------------------------------------------------------------------------------------
CONTROLE_TEMPERATURA:
	PUSH ACC
	MOV A, TEMPERATURA_ALVO
	SUBB A, ADC_V_RAW
	JC	TEMPERATURA_MAIOR
TEMPERATURA_MENOR:   ;-> temp da agua
	SETB RELE_CONTROL ;-> liga o relé
	CLR LEDVM
	MOV R6,#1
	MOV	R7,#0
	POP ACC
	RET
TEMPERATURA_MAIOR:
	CLR RELE_CONTROL ;-> desliga o relé
	SETB LEDVM
	MOV R7,#1
	MOV R6,#0
	POP ACC
	RET
;-----------------------------------------------------------------------------------------
CONTROLE_TEMPERATURA_SUBINDO:  ; quando a temperatura baixa da temperatura_alvo, só volta a ligar se baixar mais 0.8 graus
	PUSH ACC
	MOV A,#FLAG
	CJNE A,#0,LOOP_FLAG
	MOV A, TEMPERATURA_ALVO
	SUBB A, ADC_V_RAW
	JC	TEMPERATURA_ACIMA0
TEMPERATURA_ABAIXO0:
	SETB RELE_CONTROL
	CLR LEDVM
	POP ACC
	JMP ESCREVE
TEMPERATURA_ACIMA0:
	CLR RELE_CONTROL
	SETB LEDVM
	MOV FLAG,#1
	POP ACC
	JMP ESCREVE
LOOP_FLAG:	
	MOV A, TEMPERATURA_ALVO
	DEC A
	DEC A
	SUBB A, ADC_V_RAW
	JNC TEMPERATURA_ACIMA1
TEMPERATURA_ABAIXO1:
	CLR RELE_CONTROL
	SETB LEDVM
	POP ACC
	JMP ESCREVE
TEMPERATURA_ACIMA1:
	SETB RELE_CONTROL
	CLR LEDVM
	MOV FLAG,#0
	POP ACC
	JMP ESCREVE
	
;-----------------------------------------------------------------------------------------	
CONTROLE_TEMPERATURA_DESCENDO:
	PUSH ACC
	MOV A,#FLAG
	CJNE A,#0,LOOP_FLAG2
	MOV A, TEMPERATURA_ALVO
	SUBB A, ADC_V_RAW
	JNC	TEMPERATURA_ABAIXO2
TEMPERATURA_ACIMA2:
	CLR RELE_CONTROL
	SETB LEDVM
	POP ACC
	JMP ESCREVE
TEMPERATURA_ABAIXO2:
	SETB RELE_CONTROL
	CLR LEDVM
	MOV FLAG,#1
	POP ACC
	JMP ESCREVE
LOOP_FLAG2:	
	MOV A, TEMPERATURA_ALVO
	INC A
	INC A
	SUBB A, ADC_V_RAW
	JC TEMPERATURA_ACIMA3
TEMPERATURA_ABAIXO3:
	SETB RELE_CONTROL
	CLR LEDVM
	POP ACC
	JMP ESCREVE
TEMPERATURA_ACIMA3:
	CLR RELE_CONTROL
	SETB LEDVM
	MOV FLAG,#0
	POP ACC
	JMP ESCREVE

;-----------------------------------------------------------------------------------------
;	Rotina que envia o valor da temperatura para o LCD
;-----------------------------------------------------------------------------------------
TEMPERATURA_LCD:
		PUSH	ACC
		PUSH	AR0
		PUSH	AR1
		
		MOV		R0,	#0x00
		MOV		R1, #0x01
		ACALL	GOTOXY
		
		MOV		A, #0x54
		CALL	ESCDADO
		
		MOV 	A, #0x3A
		CALL	ESCDADO
		
		MOV 	A, #0x20
		CALL	ESCDADO				
		
		MOV		A,	TEMP_ADC_MSB
		ANL		A, #11110000b
		SWAP	A
		ADD		A, #0x30
		ACALL	ESCDADO
		
		MOV		A, TEMP_ADC_MSB
		ANL		A, #00001111b
		ADD		A, #0x30
		ACALL	ESCDADO
		
		MOV		A,	TEMP_ADC_LSB
		ANL		A, #11110000b
		SWAP	A
		ADD		A, #0x30
		ACALL	ESCDADO
		
		MOV		A,	#0x2E
		ACALL	ESCDADO 
		
		MOV		A, TEMP_ADC_LSB
		ANL		A, #00001111b
		ADD		A, #0x30
		ACALL	ESCDADO
		
		MOV 	A, #0x20
		CALL	ESCDADO	
		
		MOV		A,	#0x43
		ACALL	ESCDADO 
		
		POP		AR1
		POP		AR0
		POP		ACC
			
RET
;----------------------------------------------------------------------------
;FUNCAO PROXIMO ALIMENTO
;RETORNA O PROXIMO ALIMENTO DA LISTA
;-----------------------------------------------------------------------------
PROXIMO_ALIMENTO:
	MOV A,ALIMENTO_ATUAL
	INC A
	MOV ALIMENTO_ATUAL,A
	MOV R0,#ALIMENTO_ATUAL
	CJNE A,#NUM_ALIMENTO,ALIMENTO_STR
	MOV ALIMENTO_ATUAL,#0
	
	ALIMENTO_STR:
	
	CJNE @R0,#0,PROX_0
	MOV DPTR,#STR_CARNE
	JMP IMPRIME_ALIMENTO
	PROX_0:
	
	CJNE @R0,#1,PROX_1
	MOV DPTR,#STR_PEIXE
	JMP IMPRIME_ALIMENTO	
	PROX_1:
	
	CJNE @R0,#2,PROX_2
	MOV DPTR,#STR_FRANGO
	JMP IMPRIME_ALIMENTO
	PROX_2:
	
	CJNE @R0,#3,PROX_3
	MOV DPTR,#STR_TESTE
	JMP IMPRIME_ALIMENTO
	PROX_3:
	
	IMPRIME_ALIMENTO:
	CALL   ESC_STR2
	
RET
;-----------------------------------------------------------------------------------------
;FUNCAO PROXIMO PONTO
;RETORNA O PROXIMO ALIMENTO DA LISTA
;-----------------------------------------------------------------------------------------
PROXIMO_PONTO:
	MOV A,PONTO_ATUAL
	INC A
	MOV PONTO_ATUAL,A
	MOV R0,#PONTO_ATUAL
	CJNE A,#3,PONTO_STR
	MOV PONTO_ATUAL,#0

	
	PONTO_STR:
	
	CJNE @R0,#0,PROX_0_PONTO
	MOV DPTR,#STR_CARNE_MP
	JMP IMPRIME_PONTO
	PROX_0_PONTO:
	
	CJNE @R0,#1,PROX_1_PONTO
	MOV DPTR,#STR_CARNE_AP
	JMP IMPRIME_PONTO	
	PROX_1_PONTO:

	CJNE @R0,#2,PROX_2_PONTO
	MOV DPTR,#STR_CARNE_BP
	JMP IMPRIME_PONTO	
	PROX_2_PONTO:
	
	IMPRIME_PONTO:
	CALL   ESC_STR2
	
RET
;-----------------------------------------------------------------------------------------
; Rotina para ligar o RTC
;-----------------------------------------------------------------------------------------
INICIAR_RTC:
	MOV TMOD, #1
	MOV TH0,#HIGH(RESET_VALUE)
	MOV TL0,#LOW(RESET_VALUE)
	SETB ET0
	SETB EA
	SETB TR0

RET
;-----------------------------------------------------------------------------------------
; Rotina para desligar o RTC
;-----------------------------------------------------------------------------------------
DESLIGAR_RTC:
	CLR TR0
	CLR ET0
	SETB LEDAM
	CLR  LEDVM
RET
;-----------------------------------------------------------------------------------------
; Rotina de inicializacao
;-----------------------------------------------------------------------------------------
INICIALIZAR_VARIAVEIS:
	MOV R6,#0
	MOV	R7,#0
	MOV FLAG,#0
	MOV ALIMENTO_ATUAL,#0
	MOV PONTO_ATUAL,#0
	MOV SEGUNDOS,#0
	MOV MINUTOS,#0
	MOV HORAS,#0
	MOV TICKS,#20
	MOV A,#16
	ADD A,#STR_TEMP
	MOV R0,A
	MOV A,#00h
	MOVX @R0,A
	MOV A,#' '
	
	MOV R1,#16
	INICIA_VOLTA:
		DEC R0
		MOVX @R0,A
		DJNZ R1,INICIA_VOLTA 

		MOV A,#':'
		MOV R0,#STR_2P0
		MOVX @R0,A
		MOV A,#':'
		MOV R0,#STR_2P1
		MOVX @R0,A	
RET
;-----------------------------------------------------------------------------------------
; Rotina que transforma em ASCII para escrever no display
; Recebe em R0 o endereco do registrador. Retorna em A o mais significativo e em B o menos
;-----------------------------------------------------------------------------------------
REG_TO_ASCII:
	MOV A,@R0
	MOV B,#10
	DIV AB
	PUSH ACC
	MOV A,B
	ADD A,#30h
	MOV B,A
	POP ACC
	ADD A,#30h
RET
;-----------------------------------------------------------------------------------------
;	Rotina de atualizacao do tempo na tela
;-----------------------------------------------------------------------------------------
ATUALIZA_STR_TEMP:
	; horas
	MOV R0,#HORAS
	
	CALL REG_TO_ASCII
	MOV R1,#STR_HRS
	MOVX @R1,A
	INC R1
	MOV A,B
	MOVX @R1,A
	
	; min
	MOV R0,#MINUTOS
	
	CALL REG_TO_ASCII
	MOV R1,#STR_MIN
	MOVX @R1,A
	INC R1
	MOV A,B
	MOVX @R1,A
	
	; seg
	MOV R0,#SEGUNDOS
	
	CALL REG_TO_ASCII
	MOV R1,#STR_SEG
	MOVX @R1,A
	INC R1
	MOV A,B
	MOVX @R1,A
	
RET
;-----------------------------------------------------------------------------------------
;	Rotina de leitura do ADC
;-----------------------------------------------------------------------------------------
LEITURA_ADC:
	CLR		SPI_ADC_CS
				
	MOV		R0,	#0x03
	MOV		R1, #11000000b
	CALL	SPI_R_TX
		
	MOV		R0,	#0x08
	MOV		R1, #00000000b
	CALL	SPI_R_TX
	MOV 	ADC_V_RAW,R0
	
	SETB	SPI_ADC_CS
	RET
;-----------------------------------------------------------------------------------------
; 	Subrotina de inicialização da comunicação SPI por software. Os pinos de
;	 MISO, MOSI e CLK já devem estar previamente definidos.
;-----------------------------------------------------------------------------------------
SPI_R_INIT:
	SETB	SPI_MISO
	SETB	SPI_MOSI
	SETB	SPI_CLK
	RET								
;-----------------------------------------------------------------------------------------
; 	Nome:		SPI_R_TX
; 	Descricao:	Subrotina de envio/recebimento de um dado via interface SPI por software.
;				OBS: O pino de CS do periférico ja deve estar devidamente ativado.
;	Parametros de entrada:
;				R0: Numero de bits
;				R1:	Byte a ser transmitido
; 	Parametro de saida:
;				R0:	Byte recebido
;-----------------------------------------------------------------------------------------
SPI_R_TX:
		PUSH	ACC								; protege ACC
		PUSH	B								; protege B
		
		CLR		SPI_CLK							; inicia o clock em 0
		MOV		B,	R0							; B terá o numero de bits a transmitir

	SPI_R_TX_JMP0:	
			MOV		A,	R1							; rola o byte para colocar  
			RLC		A								; cada bit no carry
			MOV		R1, A							; e entao
			MOV		SPI_MOSI,	C					; enviar para o pino MOSI
			
			NOP
			SETB	SPI_CLK							; da um pulso de clock
			NOP
			NOP
			NOP
			CLR		SPI_CLK
			
			MOV 	A,	R0							
			MOV		C,	SPI_MISO					; recebe um bit simultaneamente
			RLC		A
			MOV		R0,	A							; e salva em R0
			
			DJNZ 	B, 	SPI_R_TX_JMP0				; repete para resto dos bits
			
			POP		B								; restaura B
			POP		ACC								; restaura ACC

			RET				
;-----------------------------------------------------------------------------------------
;	Rotina de interrupção do Timer 0 					
;-----------------------------------------------------------------------------------------
TIMER0_IRQ:
	PUSH ACC
	MOV TH0,#HIGH RESET_VALUE 
	MOV TL0,#LOW RESET_VALUE

	DJNZ TICKS,EXIT_RTC         ;Decrementa TICKS, se não é zero exit imediatamente 
	MOV TICKS,#(QUANTA)               ;reseta em 20, pois assim o countdown está pronto para passar outro segundo
	;dec segundo
	MOV A,SEGUNDOS
	JNZ DEC_SEG
	MOV SEGUNDOS,#60
	;dec minutos
	MOV A,MINUTOS
	JNZ DEC_MIN
	MOV MINUTOS,#60
	;dec hora
	MOV A,HORAS
	JNZ DEC_HORA
	CALL DESLIGAR_RTC
	JMP EXIT_RTC
	
	DEC_HORA:
	DEC HORAS
	DEC_MIN:
	DEC MINUTOS	
	DEC_SEG:
	DEC SEGUNDOS
	MOV NOVO_SEGUNDO,#1


EXIT_RTC:
	POP ACC            

RETI
;-----------------------------------------------------------------------------------------
;FUNCAO CHECK_DOWN'
;FAZ O DEBOUNCE DA CHAVE. RETORNA 1 SE ESTA ATIVA OU 0 SE ESTA INATIVA
;SAIDA: ACUMULADOR
;UTILIZA: A, R0
;------------------------------------------------------------------------------------------
CHECK_DOWN:
	JB SW_DOWN,CHECK_DOWN_RET0 ; se nao esta ativo volta de primeira
	MOV A,#255
	
	CHECK_DOWN_LOOP:
		MOV R0,#100
			CHECK_DOWN_LOOP2:
				JB SW_DOWN,CHECK_DOWN_RET0 ; se nao for ativo durante um tempo, sai da funcao
			DJNZ R0,CHECK_DOWN_LOOP2
		DJNZ ACC,CHECK_DOWN_LOOP
	
	MOV A,#1
	RELEASE_DOWN: 
	JNB SW_DOWN,RELEASE_DOWN
	RET
	
	CHECK_DOWN_RET0:
	MOV A,#0
RET
;-----------------------------------------------------------------------------------------
;FUNCAO CHECK_ENTER
;FAZ O DEBOUNCE DA CHAVE. RETORNA 1 SE ESTA ATIVA OU 0 SE ESTA INATIVA
;SAIDA: ACUMULADOR
;UTILIZA: A, R0
;------------------------------------------------------------------------------------------
CHECK_ENTER:
	JB SW_ENTER,CHECK_ENTER_RET0 ; se nao esta ativo volta de primeira
	MOV A,#255
	
	CHECK_ENTER_LOOP:
		MOV R0,#100
			CHECK_ENTER_LOOP2:
				JB SW_ENTER,CHECK_ENTER_RET0 ; se nao for ativo durante um tempo, sai da funcao
			DJNZ R0,CHECK_ENTER_LOOP2
		DJNZ ACC,CHECK_ENTER_LOOP
	
	MOV A,#1
	RELEASE_ENTER: 
	JNB SW_ENTER,RELEASE_ENTER
	RET
	
	CHECK_ENTER_RET0:
	MOV A,#0
RET
;-----------------------------------------------------------------------------------------
;	Look-up Table para converter de um valor 
;-----------------------------------------------------------------------------------------
TABLE_LM35_LOW_TO_BCD:
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24,	0x28,	0x32,	0x36,	0x40
	DB	0x44,	0x48,	0x52,	0x56,	0x60,	0x64,	0x68,	0x72,	0x76,	0x80
	DB	0x84,	0x88,	0x92,	0x96,	0x00,	0x04,	0x08,	0x12,	0x16,	0x20
	DB	0x24,	0x28,	0x32,	0x36,	0x40,	0x44,	0x48,	0x52,	0x56,	0x60
	DB	0x64,	0x68,	0x72,	0x76,	0x80,	0x84,	0x88,	0x92,	0x96,	0x00
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24,	0x28,	0x32,	0x36,	0x40
	DB	0x44,	0x48,	0x52,	0x56,	0x60,	0x64,	0x68,	0x72,	0x76,	0x80
	DB	0x84,	0x88,	0x92,	0x96,	0x00,	0x04,	0x08,	0x12,	0x16,	0x20
	DB	0x24,	0x28,	0x32,	0x36,	0x40,	0x44,	0x48,	0x52,	0x56,	0x60
	DB	0x64,	0x68,	0x72,	0x76,	0x80,	0x84,	0x88,	0x92,	0x96,	0x00
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24,	0x28,	0x32,	0x36,	0x40
	DB	0x44,	0x48,	0x52,	0x56,	0x60,	0x64,	0x68,	0x72,	0x76,	0x80
	DB	0x84,	0x88,	0x92,	0x96,	0x00,	0x04,	0x08,	0x12,	0x16,	0x20
	DB	0x24,	0x28,	0x32,	0x36,	0x40,	0x44,	0x48,	0x52,	0x56,	0x60
	DB	0x64,	0x68,	0x72,	0x76,	0x80,	0x84,	0x88,	0x92,	0x96,	0x00
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24,	0x28,	0x32,	0x36,	0x40
	DB	0x44,	0x48,	0x52,	0x56,	0x60,	0x64,	0x68,	0x72,	0x76,	0x80
	DB	0x84,	0x88,	0x92,	0x96,	0x00,	0x04,	0x08,	0x12,	0x16,	0x20
	DB	0x24,	0x28,	0x32,	0x36,	0x40,	0x44,	0x48,	0x52,	0x56,	0x60
	DB	0x64,	0x68,	0x72,	0x76,	0x80,	0x84,	0x88,	0x92,	0x96,	0x00
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24,	0x28,	0x32,	0x36,	0x40
	DB	0x44,	0x48,	0x52,	0x56,	0x60,	0x64,	0x68,	0x72,	0x76,	0x80
	DB	0x84,	0x88,	0x92,	0x96,	0x00,	0x04,	0x08,	0x12,	0x16,	0x20
	DB	0x24,	0x28,	0x32,	0x36,	0x40,	0x44,	0x48,	0x52,	0x56,	0x60
	DB	0x64,	0x68,	0x72,	0x76,	0x80,	0x84,	0x88,	0x92,	0x96,	0x00
	DB	0x04,	0x08,	0x12,	0x16,	0x20,	0x24
;-----------------------------------------------------------------------------------------
TABLE_LM35_HIGH_TO_BCD:
	DB	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00
	DB	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00
	DB	0x00,	0x00,	0x00,	0x00,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01
	DB	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01
	DB	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x01,	0x02
	DB	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02
	DB	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02,	0x02
	DB	0x02,	0x02,	0x02,	0x02,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03
	DB	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03
	DB	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x03,	0x04
	DB	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04
	DB	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04,	0x04
	DB	0x04,	0x04,	0x04,	0x04,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05
	DB	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05
	DB	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x05,	0x06
	DB	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06
	DB	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06,	0x06
	DB	0x06,	0x06,	0x06,	0x06,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07
	DB	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07
	DB	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x07,	0x08
	DB	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08
	DB	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08,	0x08
	DB	0x08,	0x08,	0x08,	0x08,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09
	DB	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09
	DB	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09,	0x09
	DB	0x10,	0x10,	0x10,	0x10,	0x10,	0x10
;-----------------------------------------------------------------------------------------
;***************************************************************************
;ROTINAS DE TRATAMENTO DO DISPLAY DE CRISTAL LIQUIDO 16X2
;***************************************************************************
;NOME: INIDISP
;DESCRICAO: ROTINA DE INICIALIZACAO DO DISPLAY LCD 2x16
;		PROGRAMA CARACTER 5x7, LIMPA DISPLAY E POSICIONA (0,0)
;ENTRADA: -
;SAIDA: -
;ALTERA: R0,R2

INIDISP:                       
        MOV     R0,#38H         ;UTILIZACAO: 8 BITS, 2 LINHAS, 5x7
        MOV     R2,#05          ;ESPERA 5ms
        CALL    ESCINST         ;ENVIA A INSTRUCAO
        MOV     R0,#38H         ;UTILIZACAO: 8 BITS, 2 LINHAS, 5x7
        MOV     R2,#01          ;ESPERA 1ms
        CALL    ESCINST         ;ENVIA A INSTRUCAO
        MOV     R0,#06H         ;INSTRUCAO DE MODO DE OPERACAO
        MOV     R2,#01          ;ESPERA 1ms
        CALL    ESCINST         ;ENVIA A INSTRUCAO
        MOV     R0,#0CH         ;INSTRUCAO DE CONTROLE ATIVO/INATIVO
        MOV     R2,#01          ;ESPERA 1ms
        CALL    ESCINST         ;ENVIA A INSTRUCAO
        MOV     R0,#01H         ;INSTRUCAO DE LIMPEZA DO DISPLAY
        MOV     R2,#02          ;ESPERA 2ms
        CALL    ESCINST         ;ENVIA A INSTRUCAO
        RET

;***************************************************************************
;NOME: ESCINST
;DESCRICAO: ROTINA QUE ESCREVE INSTRUCAO PARA O DISPLAY E ESPERA DESOCUPAR
;P.ENTRADA: R0 = INSTRUCAO A SER ESCRITA NO MODULO DISPLAY
;           R2 = TEMPO DE ESPERA EM ms
;P.SAIDA: -
;ALTERA: R0,R2

ESCINST:  
	CLR	RW		;MODO ESCRITA NO LCD
	CLR     RS              ;RS  = 0 (SELECIONA REG. DE INSTRUCOES)
	SETB    E_LCD           ;E = 1 (HABILITA LCD)
	MOV     P0,R0           ;INSTRUCAO A SER ESCRITA
	CLR     E_LCD           ;E = 0 (DESABILITA LCD)
	MOV	P0,#0xFF	;PORTA 0 COMO ENTRADA
	SETB	RW		;MODO LEITURA NO LCD	
	SETB    E_LCD           ;E = 1 (HABILITA LCD)	
ESCI1:	JB	BUSYF,ESCI1	;ESPERA BUSY FLAG = 0
	CLR     E_LCD           ;E = 0 (DESABILITA LCD)
        RET

;***************************************************************************
;NOME: GOTOXY
;DESCRICAO: ROTINA QUE POSICIONA O CURSOR
;P.ENTRADA: R0 = LINHA (0 A 1)
;           R1 = COLUNA (0 A 15)
;P.SAIDA: -
;DESTROI: R0,R2
GOTOXY: PUSH    ACC
        MOV     A,#80H
        CJNE    R0,#01,GT1      ;SALTA SE COLUNA 0
        MOV     A,#0C0H
GT1:    ORL     A,R1            ;CALCULA O ENDERECO DA MEMORIA DD RAM
        MOV     R0,A
        MOV     R2,#01          ;ESPERA 1ms               
        CALL    ESCINST         ;ENVIA PARA O MODULO DISPLAY
        POP     ACC
        RET
            	

;***************************************************************************
;NOME: CLR2L
;DESCRICAO: ROTINA QUE APAGA SEGUNDA LINHA DO DISPLAY LCD E POSICIONA NO INICIO
;ENTRADA: -
;SAIDA: -
;DESTROI: R0,R1
CLR2L:    
        PUSH   ACC
        MOV    R0,#01              ;LINHA
        MOV    R1,#00
        CALL   GOTOXY
        MOV    R1,#16              ;CONTADOR
CLR2L1: MOV    A,#' '              ;ESPACO
        CALL   ESCDADO
        DJNZ   R1,CLR2L1
        MOV    R0,#01              ;LINHA
        MOV    R1,#00
        CALL   GOTOXY
        POP    ACC
        RET
           
;***************************************************************************
;NOME: ESCDADO
;DESCRICAO: ROTINA QUE ESCREVE DADO PARA O DISPLAY
;ENTRADA: A = DADO A SER ESCRITA NO MODULO DISPLAY
;SAIDA: -
;DESTROI: R0           
ESCDADO:  
	CLR	RW		;MODO ESCRITA NO LCD
        SETB	RS              ;RS  = 1 (SELECIONA REG. DE DADOS)
        SETB  	E_LCD           ;LCD = 1 (HABILITA LCD)
        MOV   	P0,A            ;ESCREVE NO BUS DE DADOS
        CLR   	E_LCD           ;LCD = 0 (DESABILITA LCD)
	MOV	P0,#0xFF	;PORTA 0 COMO ENTRADA
	SETB	RW		;MODO LEITURA NO LCD
	CLR	RS		;RS = 0 (SELECIONA INSTRUÇÃO)	
	SETB    E_LCD           ;E = 1 (HABILITA LCD)
ESCD1:	JB	BUSYF,ESCD1	;ESPERA BUSY FLAG = 0
	CLR     E_LCD           ;E = 0 (DESABILITA LCD)
;        MOV     R0,#14          ;40uS
;        CALL    ATRASO
        RET

;*****************************************************************************
;NOME: MSTRING
;ROTINA QUE ESCREVE UMA STRING DA ROM NO DISPLAY A PARTIR DA POSICAO DO CURSOR
;ENTRADA: DPTR = ENDERECO INICIAL DA STRING NA MEMORIA ROM FINALIZADA POR 00H
;SAIDA: -
;DESTROI: A,DPTR,R0
MSTRING:  CLR    A
          MOVC   A,@A+DPTR      ;CARACTER DA MENSAGEM EM A
          JZ     MSTR1
          LCALL  ESCDADO        ;ESCREVE O DADO NO DISPLAY
          INC    DPTR
          SJMP   MSTRING
MSTR1:    RET
           
;*****************************************************************************
;NOME: MSTRINGX
;ROTINA QUE ESCREVE UMA STRING DA RAM NO DISPLAY A PARTIR DA POSICAO DO CURSOR
;ENTRADA: DPTR = ENDERECO INICIAL DA STRING NA MEMORIA RAM FINALIZADA POR 00H
;SAIDA: -
;DESTROI: A,DPTR,R0
MSTRINGX: MOVX   A,@DPTR        ;CARACTER DA MENSAGEM EM A
          JZ     MSTR21
          LCALL  ESCDADO        ;ESCREVE O DADO NO DISPLAY
          INC    DPTR
          SJMP   MSTRINGX
MSTR21:   RET
           
;*****************************************************************************
;NOME: ESC_STR1
;ROTINA QUE ESCREVE UMA STRING NO DISPLAY A PARTIR DO INICIO DA PRIMEIRA LINHA
;ENTRADA: DPTR = ENDERECO INICIAL DA STRING NA MEMORIA ROM FINALIZADA POR 00H
;SAIDA: -
;DESTROI: R0,A,DPTR
ESC_STR1: MOV    R0,#00         ;PRIMEIRA LINHA E PRIMEIRA COLUNA
          MOV    R1,#00
          JMP    ESC_S
          
;*****************************************************************************
;NOME: ESC_STR2
;ROTINA QUE ESCREVE UMA STRING NO DISPLAY A PARTIR DO INICIO DA SEGUNDA LINHA
;ENTRADA: DPTR = ENDERECO INICIAL DA STRING NA MEMORIA ROM FINALIZADA POR 00H
;SAIDA: -
;DESTROI: R0,A,DPTR
ESC_STR2: MOV    R0,#01         ;SEGUNDA LINHA E PRIMEIRA COLUNA
          MOV    R1,#00
ESC_S:    LCALL  GOTOXY         ;POSICIONA O CURSOR
          LCALL  MSTRING
          RET


;******************************************************************************
; NOME: CUR_ON E CUR_OFF
; FUNCAO: ROTINA CUR_ON => LIGA CURSOR DO LCD
;         ROTINA CUR_OFF => DESLIGA CURSOR DO LCD
; CHAMA: ESCINST
; ENTRADA: -
; SAIDA: -
; DESTROI: R0,R2
;******************************************************************************

CUR_ON:   MOV    R0,#0FH              ;INST.CONTROLE ATIVO (CUR ON)
          SJMP   CUR1
CUR_OFF:  MOV    R0,#0CH              ;INST. CONTROLE INATIVO (CUR OFF)
CUR1:     MOV    R2,#01
	  CALL   ESCINST              ;ENVIA A INSTRUCAO
          RET

;***************************************************************************
;NOME: Atraso
;DESCRIÇÃO: Introduz um atraso (delay) de T = (60 x R0 + 48)/fosc
;	Para fosc = 11,059MHz => R0 = 1 => T = 9,8us  a  R0 = 0 => 1,4ms
;P. ENTRADA: R0 = Valor que multiplica por 60 na fórmula (OBS.: R0 = 0 => 256)
;P. SAIDA: -
;Altera: R0
;***************************************************************************
Atraso:
	NOP			;12
	NOP			;12
	NOP			;12
	DJNZ	R0,Atraso	;24
	RET			;24


;***************************************************************************
;NOME: ATRASO_MS
;DESCRICAO: INTRODUZ UM ATRASO DE 1ms A 256ms
;P.ENTRADA: R2 = 1 => 1ms  A R2 = 0 => 256ms
;P.SAIDA: -
;ALTERA: R0,R2
ATRASO_MS:
	MOV	R0,#183		;VALOR PARA ATRASO DE 1ms
	CALL	Atraso
	MOV	R0,#183		;VALOR PARA ATRASO DE 1ms
	CALL	Atraso
	DJNZ	R2,ATRASO_MS
	RET		
	
;***************************************************************************
;NOME: ATRASO_1S
;***************************************************************************
ATRASO_1S:
	PUSH AR0
	PUSH AR1
	PUSH AR2
	
	MOV  R1,#4
	
ATRASO_1S_COUNT:
	MOV  R2,#250
	CALL ATRASO_MS
	DJNZ R1,ATRASO_1S_COUNT
	
	POP AR0
	POP AR1
	POP AR2
	
	RET	
	
;***************************************************************************
;NOME: ATRASO_500MS
;***************************************************************************

ATRASO_500MS:
	PUSH AR0
	PUSH AR1
	PUSH AR2
	
	MOV  R1,#2
	
ATRASO_500MS_COUNT:
	MOV R2,#250
	CALL ATRASO_MS
	DJNZ R1,ATRASO_500MS_COUNT
	
	POP AR0
	POP AR1
	POP AR2
	
	RET	

;***************************************************************************
;NOME: ATRASO_250MS
;***************************************************************************

ATRASO_250MS:
	PUSH AR0
	PUSH AR1
	PUSH AR2
	
	MOV R1,#1
	
ATRASO_250MS_COUNT:
	MOV R2,#250
	CALL ATRASO_MS
	DJNZ R1,ATRASO_250MS_COUNT
	
	POP AR0
	POP AR1
	POP AR2
	
	RET		

END
	