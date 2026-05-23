# iii Distributed Inference — DevOps Assignment

## Architecture

```
                        Internet
                           |
                    HTTP :3111 (public)
                           |
        +-----------------[V]---------------------+
        |         GCP VPC - us-central1           |
        |                                         |
        |  +----------------------------------+   |
        |  |  VM1 - iii-gateway (public IP)  |   |
        |  |  34.173.71.181                  |   |
        |  |  * iii engine   (ws  :49134)    |   |
        |  |  * iii-http     (http :3111)    |   |
        |  |  * iii-state, iii-queue         |   |
        |  +---------------[|]---------------+   |
        |               WebSocket :49134          |
        |         +--------+--------+             |
        |         |                 |             |
        |  +-----[V]----------+ +--[V]---------+  |
        |  | VM2 - inference  | | VM3 - caller |  |
        |  | 10.0.1.3 priv    | | 10.0.1.2 priv|  |
        |  | Python worker    | | TypeScript   |  |
        |  | Gemma-3-270M     | | caller-worker|  |
        |  | inference::      | | inference::  |  |
        |  | run_inference    | | get_response |  |
        |  +------------------+ +--------------+  |
        +-----------------------------------------+

RPC flow:
POST /v1/chat/completions
  -> iii-http (VM1)
  -> http::run_inference_over_http (VM3 TypeScript)
  -> inference::get_response (VM3)
  -> inference::run_inference (VM2 Python)
  -> Gemma-3-270M generates response
  -> result returned up the chain
```

## API

**Endpoint:** `POST http://34.173.71.181:3111/v1/chat/completions`

**Request:**
```bash
curl -X POST http://34.173.71.181:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "Say hello in one sentence."}]}' \
  --max-time 120
```

**Response:**
```json
{
  "result": {
    "0": "S", "1": "a", "2": "y",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

## Stack

| Component | VM | Language | Function |
|---|---|---|---|
| iii engine + HTTP | VM1 (public) | — | Routes RPC calls, exposes HTTP |
| caller-worker | VM3 (private) | TypeScript | Receives HTTP, calls inference worker |
| inference-worker | VM2 (private) | Python | Loads Gemma-3-270M, runs inference |

## Redeploy from scratch

### Prerequisites
- GCP account with billing enabled
- Terraform installed (`brew install hashicorp/tap/terraform`)
- gcloud CLI installed (`brew install --cask google-cloud-sdk`)

### Steps

```bash
# 1. Clone this repo
git clone https://github.com/iamsamuelk/iii-devops-assignment.git
cd iii-devops-assignment

# 2. Authenticate with GCP
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
gcloud services enable compute.googleapis.com

# 3. Generate SSH key
ssh-keygen -t ed25519 -f ~/.ssh/iii_key -N ""

# 4. Create terraform.tfvars
cat > terraform/terraform.tfvars << EOF
project_id  = "YOUR_PROJECT_ID"
ssh_pub_key = "$(cat ~/.ssh/iii_key.pub)"
EOF

# 5. Deploy
cd terraform
terraform init
terraform apply -auto-approve

# 6. Get the gateway IP
terraform output gateway_public_ip

# 7. SSH into gateway and run setup manually (see scripts/setup-gateway.sh)
# Workers connect automatically via III_URL=ws://<gateway-private-ip>:49134
```

## Production Hardening

Before putting this in production I would make the following changes:

**Security:** Restrict SSH firewall rule to my IP only instead of `0.0.0.0/0`. Add TLS termination via nginx or Caddy in front of the iii-http port so traffic is encrypted in transit. Store any secrets (HuggingFace tokens, API keys) in GCP Secret Manager rather than environment variables. Enable VPC Flow Logs for network auditing.

**Reliability:** Put the HTTP endpoint behind a GCP Load Balancer with health checks and rate limiting. Use a managed instance group for the caller-worker so it can scale horizontally under load. Add proper log aggregation (Cloud Logging) and alerting on worker failures.

**Model serving:** The inference worker currently uses the transformers CPU path. For production I would add a proper model cache so weights are not re-downloaded on every restart, and use a more efficient inference backend like llama.cpp directly.

## What I would do differently for a 100x larger model

A 100x larger model (e.g. Gemma-27B or similar) would not fit in CPU RAM on a small VM. The changes required would be:

**Hardware:** Switch the inference VM to a GPU instance (GCP A100 or L4). A single L4 (24GB VRAM) handles models up to ~13B at full precision or ~27B quantized.

**Model serving:** Replace the raw transformers loading with a dedicated inference server like vLLM or Text Generation Inference (TGI). These handle continuous batching, KV cache management, and tensor parallelism across multiple GPUs automatically.

**Model storage:** Store the GGUF weights in a GCS bucket and mount it on the inference VM at startup rather than downloading from HuggingFace every time. This makes restarts fast and avoids rate limits.

**Scaling:** With a large model, the inference VM becomes the bottleneck. I would put multiple inference VMs behind the engine, letting iii route requests across them for load balancing. The caller-worker and gateway tiers are stateless and cheap to scale.
