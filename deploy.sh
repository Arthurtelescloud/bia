#!/bin/bash

# Script de Deploy para ECS - Projeto BIA
# Versão: 1.0.0
# Autor: Amazon Q para Projeto BIA

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_ECR_REPO="863518460581.dkr.ecr.us-east-1.amazonaws.com/bia"
DEFAULT_CLUSTER="cluster-bia-alb"
DEFAULT_SERVICE="service-bia-alb"
DEFAULT_TASK_FAMILY="task-def-bia-alb"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir help
show_help() {
    cat << EOF
${BLUE}Script de Deploy para ECS - Projeto BIA${NC}

${YELLOW}DESCRIÇÃO:${NC}
    Este script automatiza o processo de build e deploy da aplicação BIA para o Amazon ECS.
    Cada imagem é taggeada com o hash do commit atual para permitir rollbacks.

${YELLOW}USO:${NC}
    $0 [OPÇÕES] COMANDO

${YELLOW}COMANDOS:${NC}
    build       Faz o build da imagem Docker e push para ECR
    deploy      Faz o deploy da aplicação para ECS
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 versões disponíveis no ECR
    help        Exibe esta ajuda

${YELLOW}OPÇÕES:${NC}
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -e, --ecr-repo REPO         Repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -f, --task-family FAMILY    Família da task definition (padrão: $DEFAULT_TASK_FAMILY)
    -t, --tag TAG               Tag específica para rollback
    -h, --help                  Exibe esta ajuda

${YELLOW}EXEMPLOS:${NC}
    # Build e push da imagem atual
    $0 build

    # Deploy da versão atual
    $0 deploy

    # Build e deploy em uma única operação
    $0 build && $0 deploy

    # Rollback para uma versão específica
    $0 rollback -t a1b2c3d

    # Listar versões disponíveis
    $0 list

    # Deploy em região diferente
    $0 deploy -r us-west-2

${YELLOW}FLUXO TÍPICO:${NC}
    1. $0 build     # Gera imagem com tag do commit atual
    2. $0 deploy    # Faz deploy da nova versão
    3. $0 list      # Lista versões para possível rollback
    4. $0 rollback -t <hash>  # Se necessário, faz rollback

${YELLOW}OBSERVAÇÕES:${NC}
    - O script usa os últimos 7 caracteres do commit hash como tag
    - Cada deploy cria uma nova task definition
    - As imagens antigas permanecem no ECR para rollback
    - É necessário ter AWS CLI configurado e permissões adequadas

EOF
}

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

# Função para verificar dependências
check_dependencies() {
    log "INFO" "Verificando dependências..."
    
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI não encontrado. Instale o AWS CLI primeiro."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker não encontrado. Instale o Docker primeiro."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log "ERROR" "Git não encontrado. Instale o Git primeiro."
        exit 1
    fi
    
    log "INFO" "Todas as dependências estão disponíveis."
}

# Função para obter hash do commit
get_commit_hash() {
    if [ -n "$ROLLBACK_TAG" ]; then
        echo "$ROLLBACK_TAG"
    else
        git rev-parse --short=7 HEAD 2>/dev/null || echo "latest"
    fi
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
        --output json 2>/dev/null || echo "{}")
    
    if [ "$current_task_def" = "{}" ]; then
        log "ERROR" "Task definition '$TASK_FAMILY' não encontrada"
        log "INFO" "Criando task definition base..."
        
        # Task definition básica para o projeto BIA
        cat > /tmp/task-definition.json << EOF
{
    "family": "$TASK_FAMILY",
    "networkMode": "bridge",
    "requiresCompatibilities": ["EC2"],
    "cpu": "256",
    "memory": "512",
    "containerDefinitions": [
        {
            "name": "bia",
            "image": "$image_uri",
            "memory": 512,
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 8080,
                    "protocol": "tcp"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/bia-tf",
                    "awslogs-region": "$REGION",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                }
            ]
        }
    ]
}
EOF
    else
        # Atualizar task definition existente com nova imagem
        echo "$current_task_def" | jq --arg image "$image_uri" '
            .containerDefinitions[0].image = $image |
            del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
        ' > /tmp/task-definition.json
    fi
    
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
        --region "$REGION" \
        --query 'service.serviceName' \
        --output text > /dev/null
    
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

# Função para rollback
rollback_application() {
    if [ -z "$ROLLBACK_TAG" ]; then
        log "ERROR" "Tag para rollback não especificada. Use -t ou --tag"
        exit 1
    fi
    
    log "INFO" "Iniciando rollback para versão: $ROLLBACK_TAG"
    
    # Verificar se a imagem existe no ECR
    aws ecr describe-images \
        --repository-name "bia" \
        --image-ids imageTag="$ROLLBACK_TAG" \
        --region "$REGION" \
        --query 'imageDetails[0].imageTags[0]' \
        --output text > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Imagem com tag '$ROLLBACK_TAG' não encontrada no ECR"
        log "INFO" "Use '$0 list' para ver versões disponíveis"
        exit 1
    fi
    
    # Fazer deploy da versão específica
    deploy_application
}

# Parsing dos argumentos
REGION="$DEFAULT_REGION"
ECR_REPO="$DEFAULT_ECR_REPO"
CLUSTER="$DEFAULT_CLUSTER"
SERVICE="$DEFAULT_SERVICE"
TASK_FAMILY="$DEFAULT_TASK_FAMILY"
ROLLBACK_TAG=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -f|--task-family)
            TASK_FAMILY="$2"
            shift 2
            ;;
        -t|--tag)
            ROLLBACK_TAG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|deploy|rollback|list|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            echo "Use '$0 help' para ver as opções disponíveis"
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [ -z "$COMMAND" ]; then
    log "ERROR" "Comando não especificado"
    echo "Use '$0 help' para ver os comandos disponíveis"
    exit 1
fi

# Executar comando
case $COMMAND in
    help)
        show_help
        ;;
    build)
        check_dependencies
        build_image
        ;;
    deploy)
        check_dependencies
        deploy_application
        ;;
    rollback)
        check_dependencies
        rollback_application
        ;;
    list)
        check_dependencies
        list_versions
        ;;
    *)
        log "ERROR" "Comando inválido: $COMMAND"
        echo "Use '$0 help' para ver os comandos disponíveis"
        exit 1
        ;;
esac
