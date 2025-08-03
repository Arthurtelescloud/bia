# Script de Deploy - Projeto BIA

## Visão Geral

O script `deploy.sh` automatiza o processo de build e deploy da aplicação BIA para o Amazon ECS, implementando versionamento baseado em commit hash para facilitar rollbacks.

## Características Principais

- **Versionamento por Commit**: Cada imagem é taggeada com os últimos 7 caracteres do commit hash
- **Rollback Simples**: Permite voltar para qualquer versão anterior facilmente
- **Task Definition Automática**: Cria automaticamente novas task definitions para cada deploy
- **Logs Coloridos**: Interface amigável com logs coloridos para melhor visualização
- **Validação de Dependências**: Verifica se todas as ferramentas necessárias estão instaladas

## Pré-requisitos

- AWS CLI configurado com credenciais adequadas
- Docker instalado e funcionando
- Git instalado
- Permissões IAM para:
  - ECR (push/pull de imagens)
  - ECS (gerenciamento de serviços e task definitions)

## Comandos Disponíveis

### Build
```bash
./deploy.sh build
```
- Faz build da imagem Docker
- Tagga com commit hash atual
- Faz push para ECR

### Deploy
```bash
./deploy.sh deploy
```
- Cria nova task definition
- Atualiza serviço ECS
- Aguarda estabilização

### Rollback
```bash
./deploy.sh rollback -t a1b2c3d
```
- Faz rollback para versão específica
- Verifica se a imagem existe no ECR

### Listar Versões
```bash
./deploy.sh list
```
- Lista últimas 10 versões disponíveis no ECR

## Fluxo de Trabalho Típico

1. **Desenvolvimento**: Faça suas alterações no código
2. **Commit**: Faça commit das alterações
3. **Build**: Execute `./deploy.sh build`
4. **Deploy**: Execute `./deploy.sh deploy`
5. **Verificação**: Teste a aplicação
6. **Rollback** (se necessário): Execute `./deploy.sh rollback -t <hash>`

## Configurações Padrão

O script usa as seguintes configurações padrão do projeto BIA:

- **Região**: us-east-1
- **ECR Repository**: 905418381762.dkr.ecr.us-east-1.amazonaws.com/bia
- **ECS Cluster**: bia-cluster-alb
- **ECS Service**: bia-service
- **Task Family**: bia-tf

## Personalização

Você pode sobrescrever as configurações padrão usando parâmetros:

```bash
# Deploy em região diferente
./deploy.sh deploy -r us-west-2

# Usar cluster diferente
./deploy.sh deploy -c meu-cluster

# Usar serviço diferente
./deploy.sh deploy -s meu-servico
```

## Exemplos de Uso

### Build e Deploy Completo
```bash
# Build da imagem atual
./deploy.sh build

# Deploy da versão atual
./deploy.sh deploy
```

### Deploy em Uma Linha
```bash
./deploy.sh build && ./deploy.sh deploy
```

### Verificar Versões e Fazer Rollback
```bash
# Listar versões disponíveis
./deploy.sh list

# Fazer rollback para versão específica
./deploy.sh rollback -t a1b2c3d
```

### Deploy com Configurações Customizadas
```bash
./deploy.sh deploy \
  -r us-west-2 \
  -c meu-cluster \
  -s meu-servico \
  -f minha-task-family
```

## Troubleshooting

### Erro de Login ECR
```bash
# Verificar credenciais AWS
aws sts get-caller-identity

# Verificar permissões ECR
aws ecr describe-repositories --region us-east-1
```

### Erro de Build Docker
```bash
# Verificar se Docker está rodando
docker ps

# Verificar Dockerfile
docker build -t test .
```

### Erro de Deploy ECS
```bash
# Verificar cluster
aws ecs describe-clusters --clusters bia-cluster-alb --region us-east-1

# Verificar serviço
aws ecs describe-services --cluster bia-cluster-alb --services bia-service --region us-east-1
```

## Estrutura da Task Definition

O script cria automaticamente uma task definition com:

- **CPU**: 256 unidades
- **Memória**: 512 MB
- **Porta**: 8080
- **Logs**: CloudWatch Logs (/ecs/bia-tf)
- **Variáveis de Ambiente**: NODE_ENV=production

## Segurança

- O script não armazena credenciais
- Usa AWS CLI configurado localmente
- Valida existência de imagens antes do rollback
- Cria logs detalhados para auditoria

## Contribuição

Para melhorar o script:

1. Teste suas alterações em ambiente de desenvolvimento
2. Mantenha a simplicidade (filosofia do projeto BIA)
3. Adicione logs informativos
4. Documente novas funcionalidades
