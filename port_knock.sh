#!/bin/bash
# script-detector-input.sh
# Script para deteccao de servicos ativados por port knocking, com input do usuario.

## CONFIGURAÇÕES FIXAS
# Porta alvo que deve abrir apos o knock
TARGET_PORT="1337"
# Timeout (em segundos) para a conexao
TIMEOUT_SEC=1

# DECLARAÇÃO DE VARIÁVEIS DE INPUT (serão preenchidas pelas funções)
SUBNET=""
KNOCK_PORTS=()

## FUNÇÃO DE LOG
function log_message() {
    echo "[$(date +'%H:%M:%S')] $1"
}

## FUNÇÃO PARA CAPTURAR A REDE
function get_network_input() {
    echo ""
    read -p "Digite o prefixo da rede a varrer (e.g., 192.168.1): " SUBNET_INPUT
    
    # Validação básica
    if [[ -z "$SUBNET_INPUT" ]]; then
        log_message " Prefixo da rede não pode ser vazio. Saindo."
        exit 1
    fi
    
    # Atribui o valor validado à variável global
    SUBNET=$SUBNET_INPUT
}

## 🚪 FUNÇÃO PARA CAPTURAR AS PORTAS DE KNOCK
function get_knock_ports_input() {
    read -p " Digite a sequencia de portas de knock (separadas por VIRGULA, e.g., 13,37,30000,3000): " PORTS_INPUT
    
    # Validação básica
    if [[ -z "$PORTS_INPUT" ]]; then
        log_message " Sequência de portas não pode ser vazia. Saindo."
        exit 1
    fi
    
    # Converte a string (separada por vírgula) para um array KNOCK_PORTS
    IFS=',' read -r -a KNOCK_PORTS <<< "$PORTS_INPUT"
}

## FUNÇÃO PARA REALIZAR O KNOCKING
function perform_knock() {
    local host_ip=$1
    log_message "Realizando KNOCK em $host_ip..."

    for port in "${KNOCK_PORTS[@]}"; do
        # Tenta usar /dev/tcp nativo do Bash
        timeout $TIMEOUT_SEC bash -c "(echo > /dev/tcp/$host_ip/$port)" &>/dev/null
        if [ $? -ne 0 ]; then
            log_message "  -> Knock falhou em $host_ip:$port. Parando..."
            return 1
        fi
        sleep 0.1 
    done
    return 0
}

##  FUNÇÃO PARA VERIFICAR A PORTA ALVO
function check_target_port() {
    local host_ip=$1
    log_message "Verificando se a porta $TARGET_PORT foi aberta em $host_ip..."

    # Usa NMAP (se disponivel) para varredura confiavel
    if command -v nmap &>/dev/null; then
        nmap_output=$(nmap -p $TARGET_PORT --open $host_ip | grep "$TARGET_PORT/tcp open")
        if [[ $nmap_output ]]; then
            return 0
        else
            return 1
        fi
    fi

    # Se NMAP nao estiver, usa /dev/tcp nativo com timeout
    timeout $TIMEOUT_SEC bash -c "(echo > /dev/tcp/$host_ip/$TARGET_PORT)" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

##  INÍCIO DO SCRIPT
clear
log_message "Iniciando configuracao da varredura de rede."

# 1. CAPTURA DOS INPUTS
get_network_input
get_knock_ports_input

# 2. INFORMAÇÕES DO SCAN
log_message "Varredura configurada para $SUBNET.0/24"
log_message "Portas de Knocking: ${KNOCK_PORTS[*]} | Porta Alvo: $TARGET_PORT"
echo "---"

# 3. LOOP DE VARREDURA
COUNTER=1
for IP_OCTET in $(seq 1 254); do
    CURRENT_IP="$SUBNET.$IP_OCTET"
    log_message "[$COUNTER/254] Testando host $CURRENT_IP..."

    if perform_knock "$CURRENT_IP"; then
        
        sleep 2 # Espera para a porta ser ativada
        if check_target_port "$CURRENT_IP"; then
            echo ""
            echo " ==========================================================="
            log_message "SERVIÇO ATIVADO ENCONTRADO em $CURRENT_IP:$TARGET_PORT!"
            echo " ==========================================================="
            
            # Tenta pegar a pagina, se wget/curl estiverem disponiveis
            log_message "Tentando obter resposta da porta $TARGET_PORT..."
            if command -v wget &>/dev/null; then
                wget -T $TIMEOUT_SEC -qO - "http://$CURRENT_IP:$TARGET_PORT"
            elif command -v curl &>/dev/null; then
                curl -m $TIMEOUT_SEC -s "http://$CURRENT_IP:$TARGET_PORT"
            else
                log_message "(Ferramentas wget ou curl não encontradas.)"
            fi
            
            echo ""
            exit 0
        else
            log_message "  -> Porta $TARGET_PORT não abriu após o knock."
        fi
    fi

    echo "---"
    ((COUNTER++))
done

log_message "Varredura completa. Nenhum serviço ativado por knock encontrado."
exit 0
