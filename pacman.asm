# TOTAL DE PIXELS: 128 colunas * 64 linhas = 8192 pixels
# LARGURA DA TELA: 128 pixels * 4 bytes = 512 bytes por linha
# +4 ? próximo pixel horizontal
# +512 ? próxima linha

### Registradores de Configuração e Controle Geral

# --- FIXOS (nunca mudam durante o programa) ---
# $5  : Endereço base do Bitmap Display (0x10010000) — via lui $5, 0x1001
# $9  : Cor das paredes do labirinto (0xEF0004 - vermelho)
# $19 : Cor do Pac-Man (0xFFFF00 - amarelo)
# $20 : Cor branca (0xFFFFFF)
# $21 : Cor preta (0x000000)
# $23 : Cor laranja/bordas do Pac-Man (0xFFA500)
#
# --- INICIALIZAÇÃO (usados só no começo, antes do game_loop) ---
# $7  : Ponteiro de escrita para pintar tela de preto (avança e é descartado)
# $8  : Ponteiro de escrita para pintar tela de branco (avança; depois vira posição fantasma 2)
# $10 : Contador dos loops de pintura (for/for1); depois vira direção fantasma 4
#
# --- GAME LOOP: posições dos fantasmas ---
# $6  : Posição atual do Fantasma 1 (Rosa)
# $8  : Posição atual do Fantasma 2 (Vermelho) — reutilizado após pintura inicial
# $14 : Posição atual do Fantasma 3 (Ciano)
# $15 : Posição atual do Fantasma 4 (Laranja) — antes era offset de duascolunas
#
# --- GAME LOOP: direções dos fantasmas (1=Cima 2=Baixo 3=Esq 4=Dir) ---
# $11 : Direção do Fantasma 1
# $12 : Direção do Fantasma 2
# $16 : Direção do Fantasma 3
# $10 : Direção do Fantasma 4 — reutilizado após pintura inicial
#
# --- ARGUMENTOS DAS FUNÇÕES DE DESENHO ---
# $25 : Ponteiro de posição de desenho (endereço do pixel inicial)
# $13 : Contador de tamanho/comprimento (linhas ou pixels a desenhar)
# $15 : Offset de distância — usado EXCLUSIVAMENTE por duascolunas
#        ATENÇÃO: conflita com posição do Fantasma 4 no game_loop!
# $9  : Cor a ser pintada (reaproveitado pelas funções de desenho)
# $22 : Cor dinâmica do fantasma (muda a cada chamada)
#
# --- FUNÇÃO atualizar_fantasma ---
# $17 : Direção atual do fantasma (entrada)
# $18 : Passo real de movimento (1px ou 1 linha) e backup de $22
# $3  : Sensor de colisão (2px ou 2 linhas �  frente)
# $2  : Offset do primeiro canto de teste / resultado do lw de cor
# $13 : Offset do segundo canto de teste (compartilhado com contador de desenho)
# $24 : Endereço calculado para teste + nova direção após sortear (saída)
# $4  : Resultado da syscall random (0 a 3)
# $sp : Pilha — salva e restaura $31
# $31 : Endereço de retorno (jal)
#
# --- CÓPIA DO CEN�?RIO ---
# $11 : Ponteiro de leitura (base do cenário original)
# $12 : Ponteiro de escrita (área reservada = base + 32256)
# $10 : Contador de pixels copiados
# $24 : Cor lida e escrita pixel a pixel
#
# --- CONFLITOS CONHECIDOS (não causam bug porque os usos não se sobrepõem) ---
# $8  : pintura inicial → posição fantasma 2 (sequencial, ok)
# $10 : contador for   → direção fantasma 4  (sequencial, ok)
# $15 : offset duascolunas → posição fantasma 4 (duascolunas só é chamada antes do game_loop)
# $11 : ponteiro leitura cópia → direção fantasma 1 (cópia termina antes do game_loop)
# $12 : ponteiro escrita cópia → direção fantasma 2 (idem)
# $13 : contador desenho → offset canto de teste em atualizar_fantasma (dentro da função, ok)
# $2  : offset canto → resultado lw → número syscall (dentro de atualizar_fantasma, sequencial)
#
# =============================================================================

.data
COR_LABIRINTO:  .word 0xEFf007f	# $9
COR_PACMAN:     .word 0xFFFF00	# $19
COR_BRANCO:     .word 0xFFFFFF	# $20
COR_PRETO:      .word 0x000000	# $21
COR_LARANJA:    .word 0xFFA500	# $23
TELA:           .word 0x10010000	# $5 , $8, $7
# A tela é pintada até ~0x1002F800 (32256 words). A FASE precisa ficar
# DEPOIS dessa área para não ser sobrescrita pela pintura do cenário.
FASE_PAD:       .space 131072		# 0x20000 de espaço (pula a área da tela)
FASE:           .word 1		# 1 = fase fácil, 2 = fase difícil

.text
main:	
	#endereço base
	lui $5, 0x1001
	lui $8, 0x1001 # usei
	#lui $7, 0x1001 
	li $10, 32256
	
	#cores
	
#	li $19, 0xffff00  # PACMAN (Amarelo) usei
	li $20, 0xFFFFFF  #branco
	li $21, 0x000000   #preto
	li $30, 0xFEFEFE  #cor das migalhas (quase-branco, diferente dos olhos)
#	li $23 0xFFA500   #laranja usei

for: 	beq $10, $0, nome
     	sw $21, 0($8)
    	addi $8, $8, 4
     	addi $10, $10, -1
     	j for
     	
nome:
	j nomes
tempo:
	jal timer
	
	li $10, 32256
	lui $8, 0x1001
	# pinta de preto
for1: 	beq $10, $0, t
     	sw $21, 0($8)
     	addi $8, $8, 4
     	addi $10, $10, -1
     	j for1
     
t:
	jal tela_inst
	jal espera_c

    	li $10,32256

	#fica preto
	lui $8, 0x1001
for2:
    beq $10,$0,desenha

    sw $21,0($8)
    addi $8,$8,4
    addi $10,$10,-1
    j for2
     
# ========================================
desenha:	
	jal desenha_fase
    	j copia_cenario
    
    
# ========================================
copia_cenario:
	lui $11, 0x1001       # Ponteiro de LEITURA 0x10010000
	addi $12, $11, 32256  # Ponteiro de ESCRITA 0x10032256
	li $10, 8192          # Contador -> (128 colunas * 64 linhas)

loop_copia:
	beq $10, $0, pmf
	lw $24, 0($11)        # Lê a cor do pixel do cenário original e guarda em $24
	sw $24, 0($12)        # Escreve essa mesma cor na cópia reserva (área livre)
	
	addi $11, $11, 4
	addi $12, $12, 4
	addi $10, $10, -1     # Decrementa
	j loop_copia
	
pmf:
    la $28, FASE
    lw $18, 0($28)

    li $3, 1
    beq $18, $3, inicializa_fase1

    li $3, 2
    beq $18, $3, inicializa_fase2

inicializa_fase1:
    # Pacman
    li $22, 0xFFFF00      # amarelo
li $23, 0xFFA500      # boca
    addi $25, $5, 0x6B00
    jal pacman

    # Fantasma rosa
    li $22, 0xFFC0CB
    addi $25, $5, 0x34DC
    jal fantasma

    # Fantasma vermelho
    li $22, 0xFF0000
    addi $25, $5, 0x352C
    jal fantasma

    # Vari�veis
    addi $7, $5, 0x6B00
    addi $6, $5, 0x34DC
    addi $8, $5, 0x352C

    li $11,1
    li $12,1

    j game_loop

inicializa_fase2:
    	# Pacman
    	li $22, 0xFFFF00      # amarelo
	li $23, 0xFFA500      # boca
    	addi $25, $5, 0x5500
    	jal pacman

    	# 4 fantasmas
    	li $22 0xFFC0CB        	#cor
	addi $25, $5, 0x34D0	#endere�o que come�a o fantasma
	jal fantasma
	
	li $22 0xFF0000
	addi $25, $5, 0x34EC	
	jal fantasma
	
	li $22 0x00FFFF
	addi $25, $5, 0x350C	
	jal fantasma
	
	li $22 0xFFA500
	addi $25, $5, 0x3528
	jal fantasma

    # Vari�veis
    addi $7,  $5, 0x5500
    addi $6,  $5, 0x34D0
    addi $8,  $5, 0x34EC
    addi $14, $5, 0x350C
    addi $15, $5, 0x3528

    li $11,1
    li $12,1
    li $16,1
    li $10,1

    j game_loop	
	
game_loop:	
caminho_pacman:
	# Leitura do teclado a cada frame
	lui $26, 0xffff
	lw $27, 0($26)
	beq $27, $0, pula_leitura
	lw $27, 4($26)
	
	# verifica se o jogador quer sair
	addi $28, $0, 'f'
	beq $27, $28, fim       # �? se apertou 'f', vai direto para "fim"

	addi $28, $0, 'd'
	bne $27, $28, n_d
	li $19, 4
n_d:	addi $28, $0, 'a'
	bne $27, $28, n_a
	li $19, 3
n_a:	addi $28, $0, 'w'
	bne $27, $28, n_w
	li $19, 1
n_w:	addi $28, $0, 's'
	bne $27, $28, n_s
	li $19, 2
n_s:
pula_leitura:

	move $25, $7           # Passa a posição atual para a rotina
	move $17, $19           # Passa a direção atual
	li $22 0xFFFF00        	#cor
	li $23 0xFFA500
	jal atualizar_pacman
	move $7, $25           # Salva a nova posição atualizada
	move $19, $24           # Salva a direção (que pode ter mudado se colidiu)
	
	# --- VERIFICA COLISÃO COM FANTASMAS ---
	beq $7, $6, reiniciar      # colidiu com Fantasma 1
	beq $7, $8, reiniciar      # colidiu com Fantasma 2
	beq $7, $14, reiniciar     # colidiu com Fantasma 3
	beq $7, $15, reiniciar     # colidiu com Fantasma 4
	
	#movimentacão fantasma 1
	move $25, $6           # Passa a posição atual para a rotina
	move $17, $11           # Passa a direção atual
	li $22, 0xFFC0CB        # Cor Rosa
	jal atualizar_fantasma
	move $6, $25           # Salva a nova posição atualizada
	move $11, $24           # Salva a direção (que pode ter mudado se colidiu)

	#movimentacão fantasma 2
	move $25, $8		# Passa a posição atual
	move $17, $12           # Passa a direção atual
	li $22, 0xFF0000        # Cor Vermelha
	jal atualizar_fantasma
	move $8, $25           # Salva a nova posição
	move $12, $24           # Salva a direção
	
	la $28, FASE
lw $18, 0($28)

li $3, 1
beq $18, $3, pula_f3_f4
	#movimentacão fantasma 3
	move $25, $14           # Passa a posição atual
	move $17, $16           # Passa a direção atual
	li $22, 0x00FFFF        # Cor Ciano
	jal atualizar_fantasma
	move $14, $25           # Salva a nova posição
	move $16, $24           # Salva a direção
	
	#movimentacão fantasma 4
	move $25, $15           # Passa a posição atual
	move $17, $10           # Passa a direção atual
	li $22, 0xFFA500        # Cor Laranja
	jal atualizar_fantasma
	move $15, $25           # Salva a nova posição
	move $10, $24           # Salva a direção
pula_f3_f4:
	# NOVA VERIFICA��O
beq $7, $6, reiniciar
beq $7, $8, reiniciar
beq $7, $14, reiniciar
beq $7, $15, reiniciar
	#tempo
	jal tim

	# --- verifica se ainda há migalhas nesta fase (lê a CÓPIA: só some o que o pacman comeu) ---
	addi $26, $5, 32256     # ponteiro = base da CÓPIA do cenário
	addi $27, $26, 32256    # fim da área de jogo na cópia
scan_migalhas:
	beq  $26, $27, fase_limpa
	lw   $28, 0($26)
	beq  $28, $30, segue_loop   # achou migalha -> ainda não acabou
	addi $26, $26, 4
	j    scan_migalhas

segue_loop:
	j game_loop             # Repete o ciclo infinitamente

# acabaram as migalhas: passa de fase
fase_limpa:
	la   $28, FASE
	lw   $2, 0($28)
	addi $2, $2, 1
	sw   $2, 0($28)
	li   $3, 3
	beq  $2, $3, fim_venceu        # passou da fase 2 -> venceu, encerra
	
	jal tela_you_win_prox         
	jal timer
	
	j    tempo              # redesenha a próxima fase (já com FASE atualizada)

# volta a posição inicial
reiniciar:

	jal tela_game_over
	jal timer
	

# Apaga o Pac-Man da posi��o atual
    move $25, $7
    jal restaura_fundo
    # Apaga o fantasma rosa
    move $25, $6
    jal restaura_fundo
    # Apaga o fantasma vermelho
    move $25, $8
    jal restaura_fundo
    # Se for fase 2, apaga tamb�m os outros dois
    la $28, FASE
    lw $18, 0($28)

    li $3, 2
    bne $18, $3, volta

    move $25, $14
    jal restaura_fundo

    move $25, $15
    jal restaura_fundo

volta:
    volta_com_mapa:
	# CORRE��O AQUI: Em vez de ir para pmf, limpa a tela de preto e redesenha o mapa!
	li $10, 32256
	lui $8, 0x1001
for_reiniciar: 
	beq $10, $0, redesenhar_tudo
	sw $21, 0($8)           # Pinta a tela de preto para tirar o "GAME OVER"
	addi $8, $8, 4
	addi $10, $10, -1
	j for_reiniciar

redesenhar_tudo:
	j desenha

	jal timer        # pequena pausa antes de recomeçar (opcional)
	j game_loop
	
fim_venceu:
	jal tela_you_win_final   # Mostra a tela de campe�o
	jal timer
	j fim
	
	
#==============================================================================
#ATUALIZAÇÃO DO FANTASMA (BORDAS REAIS + ANTICIPACAO DE 2PX)
atualizar_fantasma:
	addi $sp, $sp, -4	
	sw $31, 0($sp)        # Salva o endereço de retorno

	# 1. APAGA O FANTASMA RESTAURANDO O FUNDO DA CÓPIA
	#    (assim NÃO destrói as migalhas nem as paredes por onde passa)
	jal restaura_fundo

	# 2. CALCULA PASSO REAL (1 PX) E PASSO DO SENSOR (2 PX À FRENTE)
	# $18 = Movimento suave real (1 pixel ou 1 linha)
	# $3  = Sensor de colisão (Olha 2 pixels ou 2 linhas �  frente)
	# $2  = Canto/Extremidade Esquerda ou Superior de teste
	# $13 = Canto/Extremidade Direita ou Inferior de teste
	li $18, 0             
	beq $17, 1, cantos_cima
	beq $17, 2, cantos_baixo
	beq $17, 3, cantos_esq
	beq $17, 4, cantos_dir
	j t_colisao_ext

cantos_cima:  
	li $18, -512          # Passo real: 1 linha para cima
	li $3, -1024          # Sensor: 2 linhas para cima
	li $2, 0              # Canto esquerdo da cabeça (Pixel 0)
	li $13, 8             # Canto direito da cabeça (Pixel 8)
	j t_colisao_ext

cantos_baixo: 
	li $18, 512           # Passo real: 1 linha para baixo
	li $3, 1024           # Sensor: 2 linhas para baixo
	li $2, 2552           # Perninha mais �  esquerda (Pixel 2552)
	li $13, 2576          # Perninha mais �  direita (Pixel 2576)
	j t_colisao_ext

cantos_esq:   
	li $18, -4            # Passo real: 1 pixel para a esquerda
	li $3, -8             # Sensor: 2 pixels para a esquerda
	li $2, 508            # Borda lateral esquerda alta (Pixel 508)
	li $13, 2040          # Borda lateral esquerda baixa (Pixel 2040)
	j t_colisao_ext

cantos_dir:   
	li $18, 4             # Passo real: 1 pixel para a direita
	li $3, 8              # Sensor: 2 pixels para a direita
	li $2, 524            # Borda lateral direita alta (Pixel 524)
	li $13, 2064          # Borda lateral direita baixa (Pixel 2064)
	j t_colisao_ext

t_colisao_ext:
	# --- TESTE DA PRIMEIRA EXTREMIDADE NA CÓPIA DO CEN�?RIO ---
	add $24, $25, $3      # Posição atual + Sensor antecipado
	add $24, $24, $2      # + Offset do primeiro canto real
	addi $24, $24, 32256  # Alinha com a CÓPIA DO CEN�?RIO (0x10017e00)
	lw $2, 0($24)         # Lê a cor na cópia protegida
	beq $2, $9, colidiu_ext # Se bater na cor da parede ($9), para!

	addi $24, $24, -32256 # mesmo canto, mas na TELA real (nao reusar $2: virou cor)
	lw $2, 0($24)
	jal checa_pacman

	# --- TESTE DA SEGUNDA EXTREMIDADE NA CÓPIA DO CEN�?RIO ---
	add $24, $25, $3      # Posição atual + Sensor antecipado
	add $24, $24, $13     # + Offset do segundo canto real
	addi $24, $24, 32256  # Alinha com a CÓPIA DO CEN�?RIO
	lw $2, 0($24)         # Lê a cor na cópia protegida
	beq $2, $9, colidiu_ext # Se o outro canto também bater, para!
	
	add $24, $25, $3
	add $24, $24, $13
	lw $2, 0($24)
	jal checa_pacman

	# 3. CAMINHO LIVRE: Avança 1 pixel suavemente
	add $25, $25, $18     # Atualiza a posição com o passo real de 1px
	move $24, $17         # Mantém a direção atual
	jal fantasma          # Desenha o fantasma na nova posição
	j fim_atualizacao_ext

colidiu_ext:
	# SE COLIDIR: Redesenha o fantasma exatamente onde ele estava
	jal fantasma          
	
sortear_nova_dir_ext:
	li   $26, 8            # no m�ximo 8 tentativas
sortear_loop:
	li $2, 42             
	li $4, 0              
	li $5, 4              
	syscall               
	addi $24, $4, 1

	beq $24, $17, sortear_retry
	j sortear_ok
sortear_retry:
	addi $26, $26, -1
	bne  $26, $0, sortear_loop
	# esgotou tentativas: for�a uma dire��o diferente manualmente
	addi $24, $17, 1
	li   $27, 5
	bne  $24, $27, sortear_ok
	li   $24, 1
sortear_ok:
	lui $5, 0x1001        # Restaura o endere�o base do display em $5
fim_atualizacao_ext:
	lw $31, 0($sp)
	addi $sp, $sp, 4
	jr $31
	
checa_pacman:
    li $26, 0xFFFF00
    beq $2, $26, reiniciar
    jr $31
    	
#==============================================================================
atualizar_pacman:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # Salva o endereço de retorno

	jal come_migalhas       # come a migalha que estiver sob o Pac-Man (só o pacman come)

	move $24, $17           # retorno padrão: mantém a direção atual (evita lixo em $19)
	beq $19, $0, fim_at_ext # se não apertou nada vai voltar pro loop

	# 1. APAGA O pacman INTEGRALMENTE COM PRETO
	move $18, $22         # Salva a cor atual em $18
	move $13, $23         # Usa $13 em vez de $26 para fazer backup de $23
	move $22, $21         # Altera temporariamente para a cor Preta ($21)
	move $23, $21
	jal pacman            # Desenha o pacman em preto (apaga tudo)
	move $22, $18         # Restaura a cor original
	move $23, $13
	

	# 2. CALCULA PASSO REAL (1 PX) E PASSO DO SENSOR (2 PX À FRENTE)
	li $18, 0             
	beq $17, 1, c_cima
	beq $17, 2, c_baixo
	beq $17, 3, c_esq
	beq $17, 4, c_dir
	j t_col_ext

c_cima:  
	li $18, -512          
	li $3, -1024          
	li $2, 4              
	li $13, 1040          
	j t_col_ext

c_baixo: 
	li $18, 512           
	li $3, 1024           
	li $2, 3072           
	li $13, 3080          
	j t_col_ext

c_esq:   
	li $18, -4            
	li $3, -8             
	li $2, 508            
	li $13, 2040          
	j t_col_ext

c_dir:   
	li $18, 4             
	li $3, 8              
	li $2, 524            
	li $13, 2064          
	j t_col_ext

t_col_ext:
	# --- TESTE DA PRIMEIRA EXTREMIDADE ---
	add $24, $25, $3
	add $24, $24, $2
	addi $24, $24, 32256
	lw $2, 0($24)
	beq $2, $9, col_ext

	# fantasma (tela real)
	addi $24, $24, -32256 # mesmo canto, mas na TELA real (nao reusar $2: virou cor)
	lw $2, 0($24)
	jal checa_fantasma

	# --- TESTE DA SEGUNDA EXTREMIDADE ---
	add $24, $25, $3      
	add $24, $24, $13     
	addi $24, $24, 32256  
	lw $2, 0($24)         
	beq $2, $9, col_ext   
	
	add $24, $25, $3
	add $24, $24, $13
	lw $2, 0($24)
	jal checa_fantasma

	# 3. CAMINHO LIVRE
	add $25, $25, $18     
	move $24, $17         
	jal pacman            
	j fim_at_ext

col_ext:
	jal pacman
	move $24, $17           # bateu na parede: mantém a direção (não corrompe $19)

fim_at_ext:
	lw $31, 0($sp)
	addi $sp, $sp, 4
	jr $31
	
checa_fantasma:
    li $26, 0xFFC0CB      # rosa
    beq $2, $26, reiniciar

    li $26, 0xFF0000      # vermelho
    beq $2, $26, reiniciar

    li $26, 0x00FFFF      # ciano
    beq $2, $26, reiniciar

    li $26, 0xFFA500      # laranja
    beq $2, $26, reiniciar

    jr $31	
	
nomes:
# PACMAN
addi $25,$5,0x1E8C
li   $20,0xFFFF00      # amarelo

jal PG
addi $25,$25,48
jal AG
addi $25,$25,48
jal CG
addi $25,$25,48
jal MG
addi $25,$25,48
jal AG
addi $25,$25,48
jal NG

#"J�LIA"
addi $25,$5,0x4A60
li   $20,0xFFC0CB
jal J
addi $25,$25,24
addi $25,$25,-4
addi $25,$25,4
jal U
addi $25,$25,24
jal L
addi $25,$25,24
jal I
addi $25,$25,24
jal A

addi $25,$25,48     # espa�o
jal E
addi $25,$25,48     # espa�o

#HADASSA
li   $20,0xFFC0CB
jal H
addi $25,$25,24
jal A
addi $25,$25,24
jal D
addi $25,$25,24
jal A
addi $25,$25,24
jal S
addi $25,$25,24
jal S
addi $25,$25,24
jal A
	j tempo
	j fim
	
fim:

	
	
	addi $2, $0, 10
	syscall
	
migalha_horizontal:
    beq $13,$0,retornar

    sw $30,0($25)

    addi $25,$25,32   # distância de 8 pixels entre migalhas
    addi $13,$13,-1
    j migalha_horizontal

migalha_vertical:
    beq $13,$0,retornar

    sw $30,0($25)

    addi $25,$25,4096   # 8 linhas (8×512)
    addi $13,$13,-1
    j migalha_vertical
    
    
###############
desenhar_migalhas1:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno, pois esta rotina faz jal aninhado
#cima
addi $25,$5,0x0C20
li   $13,15
jal  migalha_horizontal

addi $25,$5,0x1C60
li   $13,11
jal  migalha_horizontal

addi $25,$5,0x1818
li   $13,6
jal  migalha_vertical

addi $25,$5,0x19E8
li   $13,6
jal  migalha_vertical

addi $25,$5,0x7430
li   $13,6
jal  migalha_horizontal

addi $25,$5,0x7538
li   $13,6
jal  migalha_horizontal

#meio
addi $25,$5,0x3060
li   $13,4
jal  migalha_vertical

addi $25,$5,0x31A0
li   $13,4
jal  migalha_vertical

#######
addi $25,$5,0x5088
li   $13,2
jal  migalha_horizontal

addi $25,$5,0x5158
li   $13,2
jal  migalha_horizontal

addi $25,$5,0x6088
li   $13,2
jal  migalha_horizontal

addi $25,$5,0x6158
li   $13,2
jal  migalha_horizontal

	lw $31, 0($sp)         # restaura o retorno correto para o chamador
	addi $sp, $sp, 4
	jr $31

###########
desenhar_migalhas2:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno, pois esta rotina faz jal aninhado
#cima
	addi $25,$5,0x0C18
	li   $13,4
	jal  migalha_horizontal

addi $25,$5,0x0CB0
li   $13,6
jal  migalha_horizontal

addi $25,$5,0x0D88
li   $13,4
jal  migalha_horizontal

#
addi $25,$5,0x1818
li   $13,6
jal  migalha_vertical

addi $25,$5,0x1850
li   $13,6
jal  migalha_vertical

#
addi $25,$5,0x19B0
li   $13,6
jal  migalha_vertical

addi $25,$5,0x19E8
li   $13,6
jal  migalha_vertical

#meio
addi $25,$5,0x32A0
li   $13,3
jal  migalha_vertical

addi $25,$5,0x3360
li   $13,3
jal  migalha_vertical

addi $25,$5,0x4264
li   $13,2
jal  migalha_horizontal

addi $25,$5,0x437C
li   $13,2
jal  migalha_horizontal

addi $25,$5,0x2470
li   $13,10
jal  migalha_horizontal
addi $25,$5,0x5C70
li   $13,10
jal  migalha_horizontal

addi $25,$5,0x3834
li   $13,2
jal  migalha_vertical
addi $25,$5,0x39CC
li   $13,2
jal  migalha_vertical

#
addi $25,$5,0x1870
li   $13,3
jal  migalha_horizontal
addi $25,$5,0x6870
li   $13,3
jal  migalha_horizontal

#
addi $25,$5,0x1950
li   $13,3
jal  migalha_horizontal
addi $25,$5,0x6950
li   $13,3
jal  migalha_horizontal

#BAIXO
addi $25,$5,0x7418
li   $13,4
jal  migalha_horizontal

addi $25,$5,0x74B0
li   $13,6
jal  migalha_horizontal
addi $25,$5,0x7588
li   $13,4
jal  migalha_horizontal
	lw $31, 0($sp)        # restaura o retorno correto para o chamador
	addi $sp, $sp, 4
jr $31

	
	
# FUNÇÕES
# ==============================================================================
pacman:	# primeira linha
    	sw $23, 0($25)
    	sw $23, 4($25)
    	sw $23, 8($25)

   	# segunda linha
    	sw $23, 508($25)
    	sw $22, 512($25)
    	sw $22, 516($25)
    	sw $22, 520($25)
   	sw $23, 524($25)

    	# terceira linha
    	sw $23, 1016($25)
    	sw $22, 1020($25)
    	sw $22, 1024($25)
    	sw $22, 1028($25)
    	sw $22, 1032($25)
    	sw $22, 1036($25)
    	sw $23, 1040($25)

    	# quarta linha
    	sw $23, 1528($25)
    	sw $22, 1532($25)
    	sw $22, 1536($25)
    	sw $22, 1540($25)
    	sw $23, 1544($25)

    	# quinta linha
    	sw $23, 2040($25)
    	sw $22, 2044($25)
    	sw $22, 2048($25)
    	sw $22, 2052($25)
    	sw $22, 2056($25)
    	sw $22, 2060($25)
    	sw $23, 2064($25)

    	# sexta linha
    	sw $23, 2556($25)
    	sw $22, 2560($25)
    	sw $22, 2564($25)
    	sw $22, 2568($25)
    	sw $23, 2572($25)

    	# sétima linha
    	sw $23, 3072($25)
    	sw $23, 3076($25)
    	sw $23, 3080($25)

    	jr $31
	
fantasma:
    	# cor do corpo
    	sw $22, 0($25)
    	sw $22, 4($25)
    	sw $22, 8($25)

    	sw $22, 508($25)
    	sw $22, 512($25)
    	sw $22, 516($25)
    	sw $22, 520($25)
    	sw $22, 524($25)

   	 # olhos
	sw $22, 1016($25)
	sw $20, 1020($25)
	sw $21, 1024($25)    # pupila esquerda
	sw $22, 1028($25)
	sw $20, 1032($25)
	sw $21, 1036($25)    # pupila direita
	sw $22, 1040($25)

    	# linha seguinte
    	sw $22, 1528($25)
    	sw $22, 1532($25)
    	sw $22, 1536($25)
    	sw $22, 1540($25)
    	sw $22, 1544($25)
    	sw $22, 1548($25)
    	sw $22, 1552($25)

    	# base
    	sw $22, 2040($25)
    	sw $22, 2044($25)
    	sw $22, 2048($25)
    	sw $22, 2052($25)
    	sw $22, 2056($25)
    	sw $22, 2060($25)
    	sw $22, 2064($25)
	
    	# perninhas
    	sw $22, 2552($25)
    	sw $22, 2560($25)
    	sw $22, 2568($25)
    	sw $22, 2576($25)
    	jr $31
coluna_dupla:
	beq $13, $0, retornar
	sw $9, 0($25)
	sw $9, 4($25)
	addi $25, $25, 512 #pula linha
	addi $13, $13, -1
	j coluna_dupla
	
coluna:
	beq $13, $0, retornar
	sw $9, 0($25)
	# sw $9, 4($25)
	addi $25, $25, 512 #pula linha
	addi $13, $13, -1
	j coluna

linha:
	beq $13, $0, retornar
	sw $9, 0($25)
	addi $25, $25, 4 #pula pixel
	addi $13, $13, -1
	j linha
	
	linha_dupla:
	beq $13, $0, retornar
	sw $9, 0($25)
	sw $9, 512($25)
	addi $25, $25, 4 #pula pixel
	addi $13, $13, -1
	j linha_dupla

duascolunas:
	beq $13, $0, retornar
	sw $9, 0($25)
	add $24, $25, $15
	sw $9, 0($24)
	addi $25, $25, 512
	addi $13, $13, -1
	j duascolunas

retornar:
	jr $31


# time fantasma
tim: 	addi $25, $0, 40000
ft: 	beq $25, $0, fimt                  
        nop
        addi $25, $25, -1
        j ft
fimt: jr $31
timer: 	addi $25, $0, 1500000
# time tela branca
fortim: beq $25, $0, fimtimer                  
        nop
        addi $25, $25, -1
        j fortim
fimtimer: jr $31

# ==============================================================================
# restaura_fundo: apaga um sprite restaurando uma caixa 7x7 a partir da CÓPIA
# do cenário (paredes + migalhas que ainda existem). NÃO destrói nada.
# Entrada: $25 = canto do sprite. Usa $2,$3,$4,$13,$24. (folha: jr $31)
restaura_fundo:
	li   $2, 7            # 7 linhas
	addi $3, $25, -8      # começa 2 colunas �  esquerda do canto
rf_linha:
	li   $4, 7            # 7 colunas
	move $13, $3
rf_col:
	lw   $24, 32256($13) # lê o fundo na CÓPIA
	sw   $24, 0($13)     # escreve de volta na tela
	addi $13, $13, 4
	addi $4, $4, -1
	bne  $4, $0, rf_col
	addi $3, $3, 512
	addi $2, $2, -1
	bne  $2, $0, rf_linha
	jr   $31

# ==============================================================================
# come_migalhas: marca como comidas (apaga na CÓPIA e na tela) as migalhas
# sob o Pac-Man. Só apaga pixels da cor de migalha ($30); paredes ficam intactas.
# Entrada: $25 = canto do Pac-Man. Usa $2,$3,$4,$13,$24. (folha: jr $31)
come_migalhas:
	li   $2, 7
	addi $3, $25, -8
cm_linha:
	li   $4, 7
	move $13, $3
cm_col:
	lw   $24, 32256($13) # cor do fundo na CÓPIA
	bne  $24, $30, cm_skip
	sw   $0, 32256($13)  # apaga a migalha na CÓPIA (comida de vez)
	sw   $0, 0($13)      # apaga a migalha na tela
cm_skip:
	addi $13, $13, 4
	addi $4, $4, -1
	bne  $4, $0, cm_col
	addi $3, $3, 512
	addi $2, $2, -1
	bne  $2, $0, cm_linha
	jr   $31

#######################CENARIOS
desenha_fase:
    la  $28, FASE
    lw  $2, 0($28)
    li  $3, 1
    beq $2, $3, fase1
    li  $3, 2
    beq $2, $3, fase2
    jr $31

fase1:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno de quem chamou fase1
	jal cenario1
	lw $31, 0($sp)         # restaura o retorno correto
	addi $sp, $sp, 4
	jr $31

fase2:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno de quem chamou fase2
	jal cenario2
	lw $31, 0($sp)         # restaura o retorno correto
	addi $sp, $sp, 4
	jr $31
# ============================================================
cenario1: 
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno de quem chamou cenario1

	li $9, 0x0000FF  #paredes do labirinto (AZUL)
	#BORDA DO CENARIO
	#esquerda
	addi $25, $5, 0x000
	addi $13, $0, 127
	jal coluna_dupla
	#direita
	addi $25, $5, 0x01F8
	addi $13, $0, 127
	jal coluna_dupla
	#cima
	addi $25, $5, 0x0000 
	addi $13, $0, 128
	jal linha_dupla
	#baixo
	addi $25, $5, 0x7C00 
	addi $13, $0, 128
	jal linha_dupla
	#======================
	######CIMA
	
	#L 
	addi $25, $5, 0x162C
	addi $13, $0, 15
	addi $15, $0, 424
	jal duascolunas
	
	addi $25, $5, 0x1E38
	addi $13, $0, 11
	addi $15, $0, 400
	jal duascolunas
	
	addi $25, $5, 0x162C
	addi $13, $0, 10
	jal linha
	
	addi $25, $5, 0x17B0
	addi $13, $0, 10
	jal linha
	
	addi $25, $5, 0x1C38
	addi $13, $0, 7
	jal linha
	
	addi $25, $5, 0x1DB0
	addi $13, $0, 7
	jal linha
	
	addi $25, $5, 0x1850
	addi $13, $0, 3
	addi $15, $0, 352
	jal duascolunas
	
	addi $25, $5, 0x322C
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x33C8
	addi $13, $0, 3
	jal linha
	
	######MEIO
	#OLHOS FORA
	#ESQUERDA
	#LINHA CIMA
	addi $25, $5, 0x2880
	addi $13, $0,15
	jal linha
	#LINHA BAIXO
	addi $25, $5, 0x4880
	addi $13, $0, 15
	jal linha
	addi $25, $5, 0x2880
	addi $13, $0, 16
	addi $15, $0, 264
	jal duascolunas
	addi $25, $5, 0x28B8
	addi $13, $0, 16
	addi $15, $0, 152
	jal duascolunas
	
	#DIREITA
	#LINHA CIMA
	addi $25, $5, 0x2950
	addi $13, $0, 15
	jal linha
	
	addi $25, $5, 0x4950
	addi $13, $0, 15
	jal linha
	
	#OLHOS DENTRO
	#ESQUERDA
	#LINHA CIMA
	addi $25, $5, 0x3160
	addi $13, $0, 7
	jal linha
	#LINHA BAIXO
	addi $25, $5, 0x3090
	addi $13, $0, 7
	jal linha
	addi $25, $5, 0x3160
	addi $13, $0, 8
	addi $15, $0, 24
	jal duascolunas
	addi $25, $5, 0x3090
	addi $13, $0, 8
	addi $15, $0, 24
	jal duascolunas
	
	#
	addi $25, $5, 0x4160
	addi $13, $0, 7
	jal linha
	
	addi $25, $5, 0x4090
	addi $13, $0, 7
	jal linha
	
	#DIREITA
	#LINHA CIMA
	addi $25, $5, 0x2950
	addi $13, $0, 15
	jal linha
	
	addi $25, $5, 0x4950
	addi $13, $0, 15
	jal linha

	#######BAIXO
	#COLUNAS
	addi $25, $5, 0x48FC
	addi $13, $0, 12
	addi $15, $0, 12
	jal duascolunas
	
	addi $25, $5, 0x48FC
	addi $13, $0, 3
	jal linha
	
	#LINHA
	addi $25, $5, 0x5EC8
	addi $13, $0, 13
	jal linha
	
	addi $25, $5, 0x5F0C
	addi $13, $0, 13
	jal linha
	
	addi $25, $5, 0x64C8
	addi $13, $0, 30
	jal linha
	
	addi $25, $5, 0x5EC8
	addi $13, $0, 3
	addi $15, $0, 116
	jal duascolunas
	
	
	#L 
	addi $25, $5, 0x4E2C
	addi $13, $0, 14
	addi $15, $0, 424
	jal duascolunas
	
	addi $25, $5, 0x4E38
	addi $13, $0, 11
	addi $15, $0, 400
	jal duascolunas
	
	addi $25, $5, 0x682C
	addi $13, $0, 10
	jal linha
	
	addi $25, $5, 0x6BB0
	addi $13, $0, 10
	jal linha
	
	addi $25, $5, 0x6238
	addi $13, $0, 7
	jal linha
	
	addi $25, $5, 0x65B0
	addi $13, $0, 7
	jal linha
	
	addi $25, $5, 0x6450
	addi $13, $0, 3
	addi $15, $0, 352
	jal duascolunas
	
	addi $25, $5, 0x4E2C
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x4FC8
	addi $13, $0, 3
	jal linha
	
	li $20, 0xFFFFFF  #branco
	jal desenhar_migalhas1

	lw $31, 0($sp)         # restaura o retorno correto de quem chamou cenario1
	addi $sp, $sp, 4
	jr $31

#====================================
cenario2:
	addi $sp, $sp, -4
	sw $31, 0($sp)        # salva o retorno de quem chamou cenario2

	li $9, 0xEFf007f   #paredes do labirinto (rosa)
	#BORDA DO CENARIO
	#esquerda
	addi $25, $5, 0x000
	addi $13, $0, 127
	jal coluna_dupla
	#direita
	addi $25, $5, 0x01F8
	addi $13, $0, 127
	jal coluna_dupla
	#cima
	addi $25, $5, 0x0000 
	addi $13, $0, 128
	jal linha_dupla
	#baixo
	addi $25, $5, 0x7C00 
	addi $13, $0, 128
	jal linha_dupla
	#=======================
	######CIMA
	#COLUNAS
	addi $25, $5, 0x0298
	addi $13, $0, 9
	addi $15, $0, 208
	jal duascolunas
	
	addi $25, $5, 0x028c
	addi $13, $0, 9
	addi $15, $0, 232
	jal duascolunas
	
	addi $25, $5, 0x1290
	addi $13, $0, 3
	jal linha
	addi $25, $5, 0x136C
	addi $13, $0, 3
	jal linha
	#LINHA
	addi $25, $5, 0x14C8
	addi $13, $0, 30
	jal linha
	addi $25, $5, 0x1AC8
	addi $13, $0, 30
	jal linha
	
	addi $25, $5, 0x14C8
	addi $13, $0, 3
	addi $15, $0, 116
	jal duascolunas
	#L 
	addi $25, $5, 0x182C
	addi $13, $0, 12
	addi $15, $0, 424
	jal duascolunas
	
	addi $25, $5, 0x1838
	addi $13, $0, 12
	addi $15, $0, 400
	jal duascolunas
	
	addi $25, $5, 0x162C
	addi $13, $0, 4
	jal linha
	
	addi $25, $5, 0x17C8
	addi $13, $0, 4
	jal linha
	
	addi $25, $5, 0x2E2C
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x2FC8
	addi $13, $0, 3
	jal linha
	
	
	######MEIO
	#ESQUERDA
	#LINHA CIMA
	addi $25, $5, 0x2E6C
	addi $13, $0, 9
	jal linha
	addi $25, $5, 0x346C
	addi $13, $0, 9
	jal linha
	
	addi $25, $5, 0x306C
	addi $13, $0, 3
	addi $15, $0, 268
	jal duascolunas
	addi $25, $5, 0x308C
	addi $13, $0, 3
	addi $15, $0, 268
	jal duascolunas
	#LINHA BAIXO
	addi $25, $5, 0x4A6C
	addi $13, $0, 9
	jal linha
	
	addi $25, $5, 0x506C
	addi $13, $0, 9
	jal linha
	
	addi $25, $5, 0x4C6C
	addi $13, $0, 3
	addi $15, $0, 268
	jal duascolunas
	
	addi $25, $5, 0x4C8C
	addi $13, $0, 3
	addi $15, $0, 268
	jal duascolunas
	#DIREITA
	#LINHA CIMA
	addi $25, $5, 0x2F78
	addi $13, $0, 9
	jal linha
	
	addi $25, $5, 0x3578
	addi $13, $0, 9
	jal linha
	#LINHA BAIXO
	addi $25, $5, 0x4B78
	addi $13, $0, 9
	jal linha
	
	addi $25, $5, 0x5178
	addi $13, $0, 9
	jal linha
	#CAIXOTE
	addi $25, $5, 0x42C8
	addi $13, $0, 30
	jal linha
	
	addi $25, $5, 0x48b8
	addi $13, $0, 38
	jal linha
	
	addi $25, $5, 0x30B8
	addi $13, $0, 13
	addi $15, $0, 148
	jal duascolunas
	
	addi $25, $5, 0x30C4
	addi $13, $0, 10
	addi $15, $0, 124
	jal duascolunas
	
	addi $25, $5, 0x2EB8
	addi $13, $0, 4
	jal linha
	
	addi $25, $5, 0x2F40
	addi $13, $0, 4
	jal linha

	
	#######BAIXO
	#COLUNAS
	addi $25, $5, 0x6C9C
	addi $13, $0, 9
	addi $15, $0, 204
	jal duascolunas
	
	addi $25, $5, 0x6C90
	addi $13, $0, 9
	addi $15, $0, 228
	jal duascolunas
	
	addi $25, $5, 0x6C90
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x6D6C
	addi $13, $0, 3
	jal linha
	#LINHA
	addi $25, $5, 0x6AC8
	addi $13, $0, 30
	jal linha
	
	addi $25, $5, 0x64C8
	addi $13, $0, 30
	jal linha
	
	addi $25, $5, 0x66C8
	addi $13, $0, 3
	addi $15, $0, 116
	jal duascolunas
	#L 
	addi $25, $5, 0x522C
	addi $13, $0, 12
	addi $15, $0, 424
	jal duascolunas
	
	addi $25, $5, 0x5238
	addi $13, $0, 12
	addi $15, $0, 400
	jal duascolunas
	
	addi $25, $5, 0x522C
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x53C8
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x682C
	addi $13, $0, 3
	jal linha
	
	addi $25, $5, 0x69CC
	addi $13, $0, 3
	jal linha
	
	li $20, 0xFFFFFF  #branco
	li $10, 0
	jal desenhar_migalhas2

	lw $31, 0($sp)         # restaura o retorno correto de quem chamou cenario2
	addi $sp, $sp, 4
	jr $31
	
##################
tela_inst:
    addi $sp, $sp, -4
    sw   $31, 0($sp)

    # PACMAN
    addi $25,$5,0x1E80
    li   $20,0xFFFF00

    jal PG
    addi $25,$25,48
    jal AG
    addi $25,$25,48
    jal CG
    addi $25,$25,48
    jal MG
    addi $25,$25,48
    jal AG
    addi $25,$25,48
    jal NG

    # TECLE C PARA COME�AR
    addi $25,$5,0x6010
    li   $20,0xFFFFFF

    jal T
    addi $25,$25,24
    jal E
    addi $25,$25,24
    jal C
    addi $25,$25,24
    jal L
    addi $25,$25,24
    jal E
    addi $25,$25,24

    li   $20,0xFFFF00
    addi $25,$25,24
    jal C
    addi $25,$25,24
    addi $25,$25,24

    li   $20,0xFFFFFF
    jal P
    addi $25,$25,24
    jal A
    addi $25,$25,24
    jal R
    addi $25,$25,24
    jal A
    addi $25,$25,24

    addi $25,$25,24
    jal C
    addi $25,$25,24
    jal O
    addi $25,$25,24
    jal M
    addi $25,$25,32
    jal E
    addi $25,$25,24
    jal C
    addi $25,$25,24
    jal A
    addi $25,$25,24
    jal R

    # CONTROLES
    addi $25,$5,0x3E6C

    li   $20,0xFFFF00
    jal W
    addi $25,$25,36
    li   $20,0xFFFFFF
    jal cima
    addi $25,$25,48

    li   $20,0xFFFF00
    jal S
    addi $25,$25,36
    li   $20,0xFFFFFF
    jal baixo
    addi $25,$25,48

    li   $20,0xFFFF00
    jal A
    addi $25,$25,36
    li   $20,0xFFFFFF
    jal esquerda
    addi $25,$25,48

    li   $20,0xFFFF00
    jal D
    addi $25,$25,36
    li   $20,0xFFFFFF
    jal direita

    lw   $31, 0($sp)
    addi $sp, $sp, 4
    jr   $31
####################
espera_c:

loop_espera:
    li $26, 0xFFFF0000
    lw $27, 0($26)
    andi $27, $27, 1
    beq $27, $zero, loop_espera
    li $26, 0xFFFF0004
    lw $27, 0($26)
    li $28, 'c'
    bne $27, $28, loop_espera
    jr $31
    
# ----- TELA ADD ------- 
    
tela_you_win_prox:
    addi $sp, $sp, -4
    sw   $31, 0($sp)

    lui  $5, 0x1001
    li   $21, 0x000000
    move $8, $5
    li   $10, 8192
yw_limpar:
    beq  $10, $0, you_win
    sw   $21, 0($8)
    addi $8, $8, 4
    addi $10, $10, -1
    j yw_limpar

you_win:
    # ---- "YOU WIN" (tamanho grande, cor amarela) ----
    li   $20, 0xFFFF00
    addi $25, $5, 0x2E64      # linha 23, centralizado

    jal  YG
    addi $25, $25, 48
    jal  OG
    addi $25, $25, 48
    jal  UG
    addi $25, $25, 68         # espa�o
    jal  WG
    addi $25, $25, 48
    jal  IG
    addi $25, $25, 40
    jal  NG

    # ---- "PROXIMA FASE" (tamanho pequeno, cor branca) ----
    li   $20, 0xFFFFFF
    addi $25, $5, 0x4864      # linha 36, centralizado

    jal  P
    addi $25, $25, 24
    jal  R
    addi $25, $25, 24
    jal  O
    addi $25, $25, 24
    jal  X
    addi $25, $25, 24
    jal  I
    addi $25, $25, 24
    jal  M
    addi $25, $25, 24
    jal  A
    addi $25, $25, 48         # espa�o
    jal  F
    addi $25, $25, 24
    jal  A
    addi $25, $25, 24
    jal  S
    addi $25, $25, 24
    jal  E

    lw   $31, 0($sp)
    addi $sp, $sp, 4
    jr   $31
    
# ---------------------
tela_game_over:
    addi $sp, $sp, -4
    sw   $31, 0($sp)

    lui  $5, 0x1001
    li   $21, 0x000000
    move $8, $5
    li   $10, 8192
go_limpar:
    beq  $10, $0, game_over
    sw   $21, 0($8)
    addi $8, $8, 4
    addi $10, $10, -1
    j    go_limpar

game_over:
    li   $20, 0xFF0000        # vermelho
    addi $25, $5, 0x3838      # linha 28, centralizado

    jal  GG
    addi $25, $25, 48
    jal  AG
    addi $25, $25, 48
    jal  MG
    addi $25, $25, 48
    jal  EG
    addi $25, $25, 88         # espa�o
    jal  OG
    addi $25, $25, 48
    jal  VG
    addi $25, $25, 48
    jal  EG
    addi $25, $25, 48
    jal  RG

    lw   $31, 0($sp)
    addi $sp, $sp, 4
    jr   $31
    
# -------------------------------- 
tela_you_win_final:
    addi $sp, $sp, -4
    sw   $31, 0($sp)

    lui  $5, 0x1001
    li   $21, 0x000000
    move $8, $5
    li   $10, 8192
ywf_limpar:
    beq  $10, $0, you_win_final
    sw   $21, 0($8)
    addi $8, $8, 4
    addi $10, $10, -1
    j    ywf_limpar

you_win_final:
    li   $20, 0xFFFF00
    addi $25, $5, 0x3860

    jal  YG
    addi $25, $25, 48
    jal  OG
    addi $25, $25, 48
    jal  UG
    addi $25, $25, 96         # espa�o
    jal  WG
    addi $25, $25, 48
    jal  IG
    addi $25, $25, 48
    jal  NG

    lw   $31, 0($sp)
    addi $sp, $sp, 4
    jr   $31
    
###################
#letras
cima:
    sw $20,   0($25)
    sw $20, 508($25)
    sw $20, 512($25)
    sw $20, 516($25)
    sw $20,1016($25)
    sw $20,1020($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,2048($25)
    jr $31
    
baixo:
    sw $20,   0($25)
    sw $20, 512($25)
    
    sw $20,1016($25)
    sw $20,1020($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    
    sw $20,1532($25)
    sw $20,1536($25)
    sw $20,1540($25)
    
    sw $20,2048($25)
    jr $31
    
esquerda:
    sw $20,4($25)
    sw $20,512($25)
    sw $20,516($25)
    sw $20,1020($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,2052($25)
    jr $31
    
direita:
    sw $20,4($25)
    sw $20,516($25)
    sw $20,520($25)
    
    sw $20,1020($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1036($25)
    
    sw $20,1540($25)
    sw $20,1544($25)
    
    sw $20,2052($25)
    jr $31

P:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,2048($25)
    jr $31

M:
    sw $20,   0($25)
    sw $20,   16($25)
    sw $20, 512($25)
    sw $20, 516($25)
    sw $20, 524($25)
    sw $20, 528($25)
    sw $20,1024($25)
    sw $20, 1032($25)
    sw $20,1040($25)
    sw $20,1536($25)
    sw $20,1552($25)
    sw $20,2048($25)
    sw $20,2064($25)
    jr $31

N:
    sw $20,   0($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 516($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2056($25)
    jr $31

J:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 516($25)
    sw $20, 1028($25)
    sw $20, 1540($25)
    sw $20, 2052($25)
    sw $20, 2048($25)
    sw $20, 2044($25)
    sw $20, 1532($25)
    
    
    jr $31

U:
    sw $20,   0($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2056($25)
    jr $31

L:
    sw $20,   0($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1536($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2056($25)
    jr $31

I:
    sw $20,   4($25)
    sw $20, 516($25)
    sw $20,1028($25)
    sw $20,1540($25)
    sw $20,2052($25)
    jr $31


A:
	sw $20,0($25)
    sw $20,   4($25)
    sw $20,8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2056($25)
    jr $31

H:
    sw $20,   0($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2056($25)
    jr $31

D:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2052($25)
    jr $31

S:
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20,1028($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2052($25)
    jr $31

T:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 516($25)
    sw $20,1028($25)
    sw $20,1540($25)
    sw $20,2052($25)
    jr $31

E:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1536($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2056($25)
    jr $31

O:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2056($25)
    jr $31

R:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20, 520($25)
    sw $20,1024($25)
    
    sw $20,1032($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,2048($25)
    sw $20,2056($25)
    jr $31

W:
    sw $20,   0($25)
    sw $20,   16($25)
    sw $20, 512($25)
    sw $20, 528($25)
    sw $20,1024($25)
    sw $20, 1032($25)#
    sw $20,1040($25)
    sw $20,1536($25)
     sw $20, 1540($25)#
    sw $20, 1548($25)#
    sw $20,1552($25)
    sw $20,2048($25)
    sw $20,2064($25)
    jr $31

C:
sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1536($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2056($25)
    jr $31


PG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20, 524($25)
    sw $20,1024($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,1544($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2560($25)
    sw $20,3072($25)
    jr $31

AG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,   12($25)
    sw $20, 512($25)
    sw $20, 524($25)
    sw $20,1024($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,1544($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2060($25)
    sw $20,2560($25)
    sw $20,2572($25)
    sw $20,3072($25)
    sw $20,3084($25)
    jr $31

CG: sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1536($25)
    sw $20,2048($25)
    sw $20,2560($25)
    sw $20,3072($25)
    sw $20,3076($25)
    sw $20,3080($25)
    sw $20,3084($25)
    jr $31

MG:
    sw $20,   0($25)
    sw $20,   16($25)
    sw $20, 512($25)
    sw $20, 516($25)
    sw $20, 524($25)
    sw $20, 528($25)
    sw $20,1024($25)
    sw $20,1032($25)
    sw $20,1040($25)
    sw $20,1536($25)
    sw $20,1552($25)
    sw $20,2048($25)
    sw $20,2064($25)
    sw $20,2560($25)
    sw $20,2576($25)
    sw $20,3072($25)
    sw $20,3088($25)
    jr $31
    
NG:
    sw $20,   0($25)
    sw $20,   16($25)#
    sw $20, 512($25)
    sw $20, 528($25)#
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1040($25)#
    sw $20,1536($25)
    sw $20,1544($25)#
    sw $20,1552($25)#
    sw $20,2048($25)
    sw $20,2060($25)#
    sw $20,2064($25)#
    sw $20,2560($25)
    sw $20,2576($25)#
    sw $20,3072($25)
    sw $20,3088($25)
    jr $31
   
# LETRAS ADICIONAIS

# ---- LETRAS PEQUENAS NOVAS (para proxima fase)
F:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1028($25)
    sw $20,1536($25)
    sw $20,2048($25)
    jr $31

X:
    sw $20,   0($25)
    sw $20,   8($25)
    sw $20, 516($25)
    sw $20,1028($25)
    sw $20,1540($25)
    sw $20,2048($25)
    sw $20,2056($25)
    jr $31

# ----- LETRAS GRANDES NOVAS ( para GAME OVER e YOU WIN)
OG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20, 524($25)
    sw $20,1024($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2060($25)
    sw $20,2560($25)
    sw $20,2572($25)
    sw $20,3072($25)
    sw $20,3076($25)
    sw $20,3080($25)
    sw $20,3084($25)
    jr $31

EG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,1544($25)
    sw $20,2048($25)
    sw $20,2560($25)
    sw $20,3072($25)
    sw $20,3076($25)
    sw $20,3080($25)
    sw $20,3084($25)
    jr $31

GG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20,1024($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2060($25)
    sw $20,2560($25)
    sw $20,2572($25)
    sw $20,3072($25)
    sw $20,3076($25)
    sw $20,3080($25)
    sw $20,3084($25)
    jr $31

VG:
    sw $20,    0($25)
    sw $20,   16($25)
    sw $20,  512($25)
    sw $20,  528($25)
    sw $20, 1024($25)
    sw $20, 1040($25)
    sw $20, 1540($25)
    sw $20, 1548($25)
    sw $20, 2052($25)
    sw $20, 2060($25)
    sw $20, 2564($25)
    sw $20, 2572($25)
    sw $20, 3080($25)
    jr $31

RG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20, 524($25)
    sw $20,1024($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1540($25)
    sw $20,1544($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2056($25)
    sw $20,2560($25)
    sw $20,2572($25)
    sw $20,3072($25)
    sw $20,3084($25)
    jr $31

YG:
    sw $20,   0($25)
    sw $20,  16($25)
    sw $20, 512($25)
    sw $20, 528($25)
    sw $20,1028($25)
    sw $20,1036($25)
    sw $20,1544($25)
    sw $20,2056($25)
    sw $20,2568($25)
    sw $20,3080($25)
    jr $31

UG:
    sw $20,   0($25)
    sw $20,  12($25)
    sw $20, 512($25)
    sw $20, 524($25)
    sw $20,1024($25)
    sw $20,1036($25)
    sw $20,1536($25)
    sw $20,1548($25)
    sw $20,2048($25)
    sw $20,2060($25)
    sw $20,2560($25)
    sw $20,2572($25)
    sw $20,3072($25)
    sw $20,3076($25)
    sw $20,3080($25)
    sw $20,3084($25)
    jr $31

WG:
    sw $20,   0($25)
    sw $20,  16($25)
    sw $20, 512($25)
    sw $20, 528($25)
    sw $20,1024($25)
    sw $20,1040($25)
    sw $20,1536($25)
    sw $20,1544($25)
    sw $20,1552($25)
    sw $20,2048($25)
    sw $20,2052($25)
    sw $20,2060($25)
    sw $20,2064($25)
    sw $20,2560($25)
    sw $20,2576($25)
    sw $20,3072($25)
    sw $20,3088($25)
    jr $31

IG:
    sw $20,   0($25)
    sw $20,   4($25)
    sw $20,   8($25)
    sw $20, 516($25)
    sw $20,1028($25)
    sw $20,1540($25)
    sw $20,2052($25)
    sw $20,2564($25)
    sw $20,3076($25)
    sw $20,3072($25)
    sw $20,3080($25)
    jr $31