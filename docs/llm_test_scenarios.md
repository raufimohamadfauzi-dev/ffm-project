# LLM Test Scenarios for FFM Assistant

**Date:** 2026-08-31
**Purpose:** Test actual Gemini Cloud responses with verified facts and analysis results

---

## Phase 2: Intent Recognition Testing

### Test Scenario 2.1: Balance Query
**Query:** "Berapa saldo saya?"
**Expected Behavior:**
- Intent classified as `queryData`
- Verified facts include current account balances
- Response grounded in verified facts
- No hallucination about account values

**Success Criteria:**
- Intent type: `FfmAssistantIntentType.queryData`
- Verified facts populated with balance data
- Response mentions actual account names and balances
- No fabricated account information

---

### Test Scenario 2.2: Transaction Recording
**Query:** "Catat pengeluaran makan 50 ribu"
**Expected Behavior:**
- Intent classified as draft creation
- Draft with correct amount and category
- Verified facts optional (not critical for mutations)
- Response shows draft preview

**Success Criteria:**
- Intent type: `FfmAssistantIntentType.createExpense`
- Draft amount: 50000
- Draft category: "makan" or similar
- Response mentions draft confirmation

---

### Test Scenario 2.3: Expense Analysis Query
**Query:** "Bagaimana pengeluaran 30 hari terakhir?"
**Expected Behavior:**
- Intent classified as `queryData`
- Verified facts include 30-day expense summary
- Analysis results populated (if implemented)
- Response grounded in actual transaction data

**Success Criteria:**
- Intent type: `FfmAssistantIntentType.queryData`
- Verified facts include recent transactions
- Response mentions period (30 hari terakhir)
- No fabricated expense values

---

### Test Scenario 2.4: Greeting
**Query:** "Halo"
**Expected Behavior:**
- Intent classified as greeting/help
- No verified facts needed
- Friendly response

**Success Criteria:**
- Intent type: `FfmAssistantIntentType.help` or similar
- Response is welcoming
- No errors

---

### Test Scenario 2.5: Capability Query
**Query:** "Apa yang bisa kamu lakukan?"
**Expected Behavior:**
- Intent classified as help
- Response lists capabilities
- No verified facts needed

**Success Criteria:**
- Intent type: `FfmAssistantIntentType.help`
- Response mentions key features
- Response is in Indonesian

---

### Test Scenario 2.6: Response Time Measurement
**Metric:** Response time for each query type
**Thresholds:**
- Simple queries (greeting, help): < 3 seconds
- Balance queries: < 5 seconds
- Analysis queries: < 10 seconds

**Success Criteria:**
- All simple queries < 3s
- Balance queries < 5s
- Analysis queries < 10s

---

## Phase 3: Analysis Query Testing

### Test Scenario 3.1: Analysis with Verified Facts
**Query:** "Berapa pengeluaran 30 hari terakhir?"
**Expected Behavior:**
- Verified facts include financial summary
- Analysis results include period analysis
- Response uses both sources
- Evidence hierarchy respected (verified facts > analysis)

**Success Criteria:**
- `verifiedFacts` field populated
- `analysisResults` field populated (if implemented)
- Response consistent with both sources
- No contradiction between sources

---

### Test Scenario 3.2: Trend Query
**Query:** "Bagaimana tren pengeluaran?"
**Expected Behavior:**
- Verified facts include trend data
- Analysis results include trend analysis
- Response shows trend direction
- Uses actual historical data

**Success Criteria:**
- `verifiedFacts` includes trend information
- Response mentions trend (naik/turun/stabil)
- Trend based on real data
- No fabricated trend claims

---

### Test Scenario 3.3: Pattern Query
**Query:** "Pengeluaran paling sering di kategori apa?"
**Expected Behavior:**
- Verified facts include category frequency
- Analysis results include frequency analysis
- Response identifies top category
- Uses actual transaction data

**Success Criteria:**
- `verifiedFacts` includes category breakdown
- Response identifies specific category
- Category based on real data
- No incorrect frequency claims

---

### Test Scenario 3.4: Grounding Verification
**Query:** "Jelaskan pengeluaran bulan ini"
**Expected Behavior:**
- All numbers in response grounded in verified facts
- No hallucinated financial values
- Analysis results used for context
- Response mentions data source

**Success Criteria:**
- All financial numbers match database
- No ungrounded numbers
- Response indicates data is from FFM
- Evaluation framework passes factuality check

---

### Test Scenario 3.5: Hallucination Check
**Query:** "Berapa pengeluaran untuk liburan?"
**Expected Behavior:**
- If no vacation transactions, response says no data
- Does not fabricate vacation expenses
- Verified facts checked for category
- Honest "no data" response

**Success Criteria:**
- No fabricated vacation expenses
- Response indicates no data if true
- Evaluation framework detects no hallucination
- Factuality score > 0.8

---

## Phase 4: Multi-turn Conversation Testing

### Test Scenario 4.1: Follow-up Query
**Conversation:**
1. User: "Berapa saldo saya?"
2. Assistant: [balance response]
3. User: "Yang tadi"

**Expected Behavior:**
- Context maintained across turns
- Follow-up understands previous query
- Verified facts for follow-up
- Consistent with previous response

**Success Criteria:**
- Follow-up refers to balance
- Context persistence works
- No contradiction with previous answer
- Memory maintained correctly

---

### Test Scenario 4.2: Create then Confirm
**Conversation:**
1. User: "Catat beli makan 50rb"
2. Assistant: [draft preview]
3. User: "Sip" or "Ya"

**Expected Behavior:**
- Draft created in first turn
- Confirmation in second turn
- Transaction saved after confirmation
- Verified facts updated after save

**Success Criteria:**
- Draft shows correct values
- Confirmation triggers save
- Transaction appears in database
- Subsequent queries reflect new transaction

---

### Test Scenario 4.3: Create then Correct
**Conversation:**
1. User: "Catat beli makan 50rb"
2. Assistant: [draft preview]
3. User: "Ubah jadi 30rb"

**Expected Behavior:**
- Draft created in first turn
- Correction in second turn
- Draft updated
- Final confirmation saves corrected value

**Success Criteria:**
- Initial draft: 50000
- Corrected draft: 30000
- Final save: 30000
- Response acknowledges correction

---

### Test Scenario 4.4: Multi-tool Conversation
**Conversation:**
1. User: "Cek saldo"
2. Assistant: [balance response]
3. User: "Catat pengeluaran 10rb"

**Expected Behavior:**
- First query: balance check
- Second query: expense creation
- Different intents handled correctly
- Context maintained

**Success Criteria:**
- First intent: queryData
- Second intent: createExpense
- Both handled correctly
- No context contamination

---

## Phase 5: Error Scenario Testing

### Test Scenario 5.1: Empty Database
**Setup:** No transactions in database
**Query:** "Berapa pengeluaran bulan ini?"

**Expected Behavior:**
- Response indicates no data
- Does not fabricate expenses
- Graceful degradation
- Suggests adding transactions

**Success Criteria:**
- Response: "Belum ada transaksi" or similar
- No fabricated values
- No crashes
- Helpful suggestion

---

### Test Scenario 5.2: Gemini API Failure
**Setup:** Mock Gemini API failure
**Query:** "Jelaskan keuangan saya"

**Expected Behavior:**
- Falls back to local response
- Error message appropriate
- No crash
- Suggests checking connection

**Success Criteria:**
- Error not silent
- Fallback response provided
- App remains stable
- User informed of issue

---

### Test Scenario 5.3: Network Timeout
**Setup:** Mock network timeout
**Query:** Any Gemini query

**Expected Behavior:**
- Timeout handled gracefully
- Fallback to local
- No indefinite loading
- Clear error message

**Success Criteria:**
- Timeout detected
- Fallback provided
- UI not stuck
- Error message clear

---

## Phase 6: Evaluation Framework Testing

### Test Scenario 6.1: Factuality Score
**Query:** "Berapa saldo saya?"
**Evaluation:**
- Run LLM evaluation framework
- Measure factuality score
- Target: > 0.8

**Success Criteria:**
- Factuality score > 0.8
- No hallucinated values
- All numbers grounded
- Evidence hierarchy respected

---

### Test Scenario 6.2: Hallucination Score
**Query:** "Jelaskan pengeluaran liburan"
**Evaluation:**
- Run LLM evaluation framework
- Measure hallucination score
- Target: < 0.2 (low hallucination)

**Success Criteria:**
- Hallucination score < 0.2
- No fabricated categories
- No fabricated amounts
- Honest "no data" if applicable

---

### Test Scenario 6.3: Intent Following Score
**Query:** "Catat pengeluaran 50rb"
**Evaluation:**
- Run LLM evaluation framework
- Measure intent following score
- Target: > 0.9

**Success Criteria:**
- Intent following score > 0.9
- Correct intent type
- Correct draft values
- No intent misclassification

---

### Test Scenario 6.4: Overall Quality Score
**Query:** Various test queries
**Evaluation:**
- Run LLM evaluation framework
- Measure overall quality
- Target: > 0.8 average

**Success Criteria:**
- Average quality > 0.8
- Consistent across queries
- No critical failures
- Evaluation report generated

---

### Test Scenario 6.5: Metrics Tracking
**Query:** All test scenarios
**Evaluation:**
- Track metrics over time
- Generate evaluation reports
- Identify regressions
- Document scores

**Success Criteria:**
- Metrics logged
- Reports generated
- Regressions detected
- Historical data available

---

## Test Execution Order

1. **Phase 2.1-2.6:** Intent Recognition (must pass first)
2. **Phase 3.1-3.5:** Analysis Queries (requires intent recognition)
3. **Phase 4.1-4.4:** Multi-turn (requires single-turn working)
4. **Phase 5.1-5.3:** Error Scenarios (can run in parallel)
5. **Phase 6.1-6.5:** Evaluation Framework (requires responses to evaluate)

---

## Notes

- All tests should be run with real Gemini API credentials
- Test data should be representative of real usage
- Each scenario should be documented with actual response
- Screenshots or logs should be saved for review
- Failures should be documented with root cause analysis
- Test environment should match production configuration as closely as possible
