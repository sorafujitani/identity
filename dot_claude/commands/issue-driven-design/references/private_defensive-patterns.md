# Defensive Design Patterns

設計の防御的レビューで使用するチェックリストとパターン集。

## Data Integrity Patterns

### Pattern: Optimistic Locking
**When**: 競合が稀で、リトライが許容される場合
**How**: version カラムを使用し、UPDATE時に検証
```sql
UPDATE users 
SET name = 'new', version = version + 1 
WHERE id = 1 AND version = 5;
-- affected_rows = 0 なら競合発生
```
**Trade-off**: 高競合時はリトライコスト増大

### Pattern: Pessimistic Locking
**When**: 競合が頻発し、確実な排他が必要な場合
**How**: SELECT FOR UPDATE でロック取得
```sql
BEGIN;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- 他トランザクションはここでブロック
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
```
**Trade-off**: スループット低下、デッドロックリスク

### Pattern: Saga Pattern
**When**: 分散トランザクションが必要な場合
**How**: 各ステップに補償トランザクションを定義
```
Order Saga:
1. Create Order → Compensate: Cancel Order
2. Reserve Inventory → Compensate: Release Inventory  
3. Process Payment → Compensate: Refund Payment
4. Ship Order → Compensate: Cancel Shipment
```
**Trade-off**: 実装複雑性、Eventually Consistent

### Pattern: Outbox Pattern
**When**: DB更新とメッセージ送信の整合性が必要な場合
**How**: 同一トランザクションでOutboxテーブルに書き込み、別プロセスで送信
```sql
BEGIN;
INSERT INTO orders (id, ...) VALUES (...);
INSERT INTO outbox (aggregate_id, event_type, payload) 
VALUES (order_id, 'OrderCreated', '...');
COMMIT;
-- 別プロセスがoutboxをポーリングして送信
```
**Trade-off**: 追加のポーリング処理、順序保証の複雑性

## Security Patterns

### Pattern: Defense in Depth
**Layers**:
1. **Network**: VPC, Security Groups, WAF
2. **Application**: Input validation, Output encoding
3. **Data**: Encryption at rest/transit, Access control
4. **Monitoring**: Audit logs, Anomaly detection

### Pattern: Principle of Least Privilege
**Checklist**:
- [ ] IAMロールは必要最小限の権限のみ
- [ ] DBユーザーはアプリ単位で分離
- [ ] API キーはスコープを限定
- [ ] 一時的な権限昇格にはAssumeRole使用

### Pattern: Secrets Management
**Do**:
- Secrets Manager / Parameter Store に格納
- アプリ起動時に取得、メモリ上に保持
- ローテーション自動化

**Don't**:
- 環境変数にハードコード
- ソースコードに埋め込み
- ログに出力

### Pattern: Input Validation
```typescript
// Schema-based validation (Zod example)
const UserInput = z.object({
  email: z.string().email().max(255),
  age: z.number().int().min(0).max(150),
  name: z.string().min(1).max(100).regex(/^[\p{L}\s]+$/u),
});

// Sanitize before use
const sanitized = DOMPurify.sanitize(userInput.bio);
```

## Resilience Patterns

### Pattern: Circuit Breaker
**States**: Closed → Open → Half-Open → Closed
**Config**:
```yaml
circuit_breaker:
  failure_threshold: 5        # Open after 5 failures
  success_threshold: 3        # Close after 3 successes in half-open
  timeout: 30s                # Time in open state before half-open
```
**Implementation**: resilience4j, polly, cockatiel

### Pattern: Retry with Exponential Backoff
```typescript
async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelay: number = 1000
): Promise<T> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      const delay = baseDelay * Math.pow(2, i) + Math.random() * 1000;
      await sleep(delay);
    }
  }
  throw new Error('Unreachable');
}
```

### Pattern: Bulkhead
**Purpose**: 障害の影響範囲を限定
**Implementation**:
- スレッドプール分離
- 接続プール分離
- サービス間のリソース割り当て制限

### Pattern: Timeout
**Guideline**:
- 外部API呼び出し: 3-10秒
- DB クエリ: 1-5秒
- 内部サービス: 1-3秒

```typescript
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 5000);

try {
  const response = await fetch(url, { signal: controller.signal });
} finally {
  clearTimeout(timeoutId);
}
```

## Observability Patterns

### Pattern: Structured Logging
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "service": "order-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "user_id": "user_789",
  "action": "create_order",
  "order_id": "ord_xyz",
  "duration_ms": 150,
  "message": "Order created successfully"
}
```

### Pattern: Distributed Tracing
**Propagation**: trace_id, span_id をHTTPヘッダで伝播
```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
```

### Pattern: Metric Types
- **Counter**: 単調増加（リクエスト数、エラー数）
- **Gauge**: 現在値（接続数、キューサイズ）
- **Histogram**: 分布（レイテンシ、サイズ）

### Pattern: Health Check
```typescript
// Liveness: プロセスが生きているか
app.get('/health/live', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Readiness: リクエストを受け付けられるか
app.get('/health/ready', async (req, res) => {
  const dbOk = await checkDatabase();
  const cacheOk = await checkCache();
  
  if (dbOk && cacheOk) {
    res.status(200).json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not_ready', db: dbOk, cache: cacheOk });
  }
});
```

## Testing Patterns

### Pattern: Test Pyramid
```
        /\
       /  \      E2E Tests (少数)
      /----\
     /      \    Integration Tests (中程度)
    /--------\
   /          \  Unit Tests (多数)
  /------------\
```

### Pattern: Contract Testing
**Purpose**: サービス間のAPI契約を検証
**Tools**: Pact, Spring Cloud Contract

### Pattern: Chaos Engineering
**Experiments**:
- Network latency injection
- Service instance termination
- Resource exhaustion
- Clock skew

**Principles**:
1. 定常状態の仮説を立てる
2. 実世界のイベントを模倣
3. 本番環境で実験
4. 影響範囲を最小化

### Pattern: Property-Based Testing
```typescript
import * as fc from 'fast-check';

test('encode/decode roundtrip', () => {
  fc.assert(
    fc.property(fc.string(), (input) => {
      expect(decode(encode(input))).toBe(input);
    })
  );
});
```
