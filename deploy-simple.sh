#!/bin/bash

# Script de Deploy Simplificado para ECS - Projeto BIA
# Versão: 1.1.0
# Autor: Amazon Q para Projeto BIA

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="863518460581.dkr.ecr.us-east-1.amazonaws.com/bia"
CLUSTER="cluster-bia-alb"
SERVICE="service-bia-alb"
TASK_FAMILY="task-def-bia-alb"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Função para obter hash do commit
get_commit_hash() {
    git rev-parse --short=7 HEAD 2>/dev/null || echo "latest"
}

# Função para fazer login no ECR
ecr_login() {
    log "INFO" "Fazendo login no ECR..."
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO" || {
        log "ERROR" "Falha no login do ECR"
        exit 1
    }
}

# Função para build da imagem
build_image() {
    log "INFO" "Iniciando build da imagem..."
    
    local commit_hash=$(get_commit_hash)
    local image_tag="$ECR_REPO:$commit_hash"
    local latest_tag="$ECR_REPO:latest"
    
    log "INFO" "Commit hash: $commit_hash"
    log "INFO" "Tag da imagem: $image_tag"
    
    # Build da imagem
    log "INFO" "Executando docker build..."
    docker build -t "$latest_tag" . || {
        log "ERROR" "Falha no build da imagem"
        exit 1
    }
    
    # Tag com commit hash
    docker tag "$latest_tag" "$image_tag"
    
    # Login no ECR
    ecr_login
    
    # Push das imagens
    log "INFO" "Fazendo push da imagem latest..."
    docker push "$latest_tag"
    
    log "INFO" "Fazendo push da imagem com tag $commit_hash..."
    docker push "$image_tag"
    
    log "INFO" "Build concluído com sucesso!"
    log "INFO" "Imagem disponível em: $image_tag"
}

# Função para criar nova task definition
create_task_definition() {
    local commit_hash=$1
    local image_uri="$ECR_REPO:$commit_hash"
    
    log "INFO" "Criando nova task definition..."
    log "DEBUG" "Imagem: $image_uri"
    
    # Obter task definition atual
    local current_task_def=$(aws ecs describe-task-definition \
        --task-definition "$TASK_FAMILY" \
        --region "$REGION" \
        --query 'taskDefinition' \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Task definition '$TASK_FAMILY' não encontrada"
        exit 1
    fi
    
    # Atualizar task definition existente com nova imagem
    echo "$current_task_def" | jq --arg image "$image_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ' > /tmp/task-definition.json
    
    # Registrar nova task definition
    local new_task_def_arn=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/task-definition.json \
        --region "$REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    if [ $? -eq 0 ]; then
        log "INFO" "Nova task definition criada: $new_task_def_arn"
        echo "$new_task_def_arn"
    else
        log "ERROR" "Falha ao criar task definition"
        exit 1
    fi
    
    # Limpar arquivo temporário
    rm -f /tmp/task-definition.json
}

# Função para fazer deploy
deploy_application() {
    log "INFO" "Iniciando deploy da aplicação..."
    
    local commit_hash=$(get_commit_hash)
    log "INFO" "Deploy da versão: $commit_hash"
    
    # Criar nova task definition
    local task_def_arn=$(create_task_definition "$commit_hash")
    
    # Atualizar serviço ECS
    log "INFO" "Atualizando serviço ECS..."
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$task_def_arn" \
        --region "$REGION" > /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Serviço atualizado com sucesso!"
        log "INFO" "Aguardando estabilização do serviço..."
        
        # Aguardar estabilização
        aws ecs wait services-stable \
            --cluster "$CLUSTER" \
            --services "$SERVICE" \
            --region "$REGION"
        
        if [ $? -eq 0 ]; then
            log "INFO" "Deploy concluído com sucesso!"
            log "INFO" "Versão deployada: $commit_hash"
            
            # Testar aplicação
            log "INFO" "Testando aplicação..."
            local app_url="http://3.237.236.119"
            local version=$(curl -s "$app_url/api/versao" || echo "Erro ao conectar")
            log "INFO" "Aplicação respondendo: $version"
            log "INFO" "URL da aplicação: $app_url"
        else
            log "WARN" "Timeout aguardando estabilização do serviço"
            log "INFO" "Verifique o status do serviço no console AWS"
        fi
    else
        log "ERROR" "Falha ao atualizar serviço ECS"
        exit 1
    fi
}

# Função para listar versões
list_versions() {
    log "INFO" "Listando últimas versões disponíveis no ECR..."
    
    aws ecr describe-images \
        --repository-name "bia" \
        --region "$REGION" \
        --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' \
        --output table || {
        log "ERROR" "Falha ao listar imagens do ECR"
        exit 1
    }
}

# Função principal
main() {
    case "${1:-help}" in
        "build")
            build_image
            ;;
        "deploy")
            deploy_application
            ;;
        "build-deploy")
            build_image
            deploy_application
            ;;
        "list")
            list_versions
            ;;
        "help"|*)
            cat << EOF
${BLUE}Script de Deploy Simplificado - Projeto BIA${NC}

${YELLOW}COMANDOS:${NC}
    build           Faz o build da imagem Docker e push para ECR
    deploy          Faz o deploy da aplicação para ECS
    build-deploy    Faz build e deploy em sequência
    list            Lista as últimas 10 versões disponíveis no ECR
    help            Exibe esta ajuda

${YELLOW}EXEMPLOS:${NC}
    $0 build-deploy    # Build e deploy completo
    $0 build           # Apenas build
    $0 deploy          # Apenas deploy
    $0 list            # Listar versões

${YELLOW}CONFIGURAÇÃO ATUAL:${NC}
    Região: $REGION
    ECR: $ECR_REPO
    Cluster: $CLUSTER
    Serviço: $SERVICE
    Task Family: $TASK_FAMILY
EOF
            ;;
    esac
}

# Executar função principal
main "$@"
