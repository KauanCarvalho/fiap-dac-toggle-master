#!/bin/bash
set -e

echo ">>> Criando fila SQS: evaluation-events"
awslocal sqs create-queue --queue-name evaluation-events

echo ">>> Criando tabela DynamoDB: analytics-events"
awslocal dynamodb create-table \
  --table-name analytics-events \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo ">>> LocalStack init concluído"
