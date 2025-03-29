Application.ensure_all_started(:mimic)

# For HTTP tests
Mimic.copy(Req.Request)

# For gRPC tests
Mimic.copy(GRPC.Stub)
Mimic.copy(Flagd.Evaluation.V1.Service.Stub)
Mimic.copy(OpenFeature.EventEmitter)
Mimic.copy(Task)

ExUnit.start()
