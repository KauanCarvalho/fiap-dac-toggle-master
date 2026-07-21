package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/go-redis/redis/v8"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Contexto global para o Redis
var ctx = context.Background()

// App struct para injeção de dependência
type App struct {
	RedisClient         *redis.Client
	SqsSvc              *sqs.SQS
	SqsQueueURL         string
	HttpClient          *http.Client
	FlagServiceURL      string
	TargetingServiceURL string
}

func main() {
	// Inicializa o OTel Tracer Provider
	shutdownTracer, err := initTracer("evaluation-service")
	if err != nil {
		log.Printf("Aviso: Falha ao inicializar tracer OTel: %v", err)
	} else {
		defer shutdownTracer(context.Background())
	}

	// Inicializa o OTel Meter Provider (métricas HTTP — Fase 4)
	shutdownMeter, err := initMeter("evaluation-service")
	if err != nil {
		log.Printf("Aviso: Falha ao inicializar meter OTel: %v", err)
	} else {
		defer shutdownMeter(context.Background())
	}

	_ = godotenv.Load() // Carrega .env para dev local

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL deve ser definida (ex: redis://localhost:6379)")
	}

	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	if flagSvcURL == "" {
		log.Fatal("FLAG_SERVICE_URL deve ser definida")
	}

	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	if targetingSvcURL == "" {
		log.Fatal("TARGETING_SERVICE_URL deve ser definida")
	}

	// SQS é opcional no dev local, mas obrigatório em prod
	sqsQueueURL := os.Getenv("AWS_SQS_URL")
	awsRegion := os.Getenv("AWS_REGION")
	if sqsQueueURL == "" {
		log.Println("Atenção: AWS_SQS_URL não definida. Eventos não serão enviados.")
	}
	if awsRegion == "" && sqsQueueURL != "" {
		log.Fatal("AWS_REGION deve ser definida para usar SQS")
	}

	// --- Inicializa Clientes ---

	// Cliente Redis
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
	}
	rdb := redis.NewClient(opt)
	if _, err := rdb.Ping(ctx).Result(); err != nil {
		log.Fatalf("Não foi possível conectar ao Redis: %v", err)
	}
	log.Println("Conectado ao Redis com sucesso!")

	// Cliente SQS (AWS SDK)
	var sqsSvc *sqs.SQS
	if sqsQueueURL != "" {
		awsConfig := &aws.Config{
			Region: aws.String(awsRegion),
		}

		endpointURL := os.Getenv("AWS_ENDPOINT_URL")
		if endpointURL != "" {
			awsConfig.Endpoint = aws.String(endpointURL)
			awsConfig.S3ForcePathStyle = aws.Bool(true)
		}

		sess, err := session.NewSession(awsConfig)
		if err != nil {
			log.Fatalf("Não foi possível criar sessão AWS: %v", err)
		}
		sqsSvc = sqs.New(sess)
		log.Println("Cliente SQS inicializado com sucesso.")
	}

	// Cliente HTTP instrumentado com OTel para propagação de contexto trace
	httpClient := &http.Client{
		Timeout:   5 * time.Second,
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	// Cria a instância da App
	app := &App{
		RedisClient:         rdb,
		SqsSvc:              sqsSvc,
		SqsQueueURL:         sqsQueueURL,
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
	}

	// --- Rotas ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	log.Printf("Serviço de Avaliação (Go) rodando na porta %s", port)

	// Métricas HTTP (Fase 4): http_requests_total / http_request_duration_seconds
	metricsRecorder, err := newHTTPMetrics("evaluation-service")
	if err != nil {
		log.Fatalf("Falha ao criar métricas HTTP: %v", err)
	}

	// Encapsula o handler principal com OTel HTTP middleware (tracing) + métricas
	otelHandler := otelhttp.NewHandler(mux, "evaluation-service-http")
	handler := metricsRecorder.middleware(otelHandler)

	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}
