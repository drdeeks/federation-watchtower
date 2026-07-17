# Complete Files Principle

## Core Principle
Create real, complete, wholesome files - never stubs, placeholders, or TODOs in production code.

## Why This Matters
- Stubs create technical debt that must be paid later
- Placeholders give false sense of progress
- Incomplete files break CI/CD and validation pipelines
- Team members cannot rely on file contents for implementation

## Enterprise Standards Applied
1. **Zero-Tolerance for Stubs**: Reject any file containing only TODO/FIXME/TBD/WIP markers
2. **Validation Gate**: Every file must pass `enterprise-org.py validate --strict` before phase completion
3. **Self-Verification**: Files must contain working code, not scaffolding
4. **Rollback Verification**: Ability to revert to previous complete state must be verified

## Implementation Guidelines
When creating any file:
- ✅ Write complete, functional code
- ✅ Include proper error handling
- ✅ Add validation/logging where appropriate
- ✅ Follow existing patterns and conventions
- ✅ Ensure file can be compiled/executed independently
- ❌ Do not leave TODOs/FIXMEs in production code
- ❌ Do not create empty function/class stubs
- ❌ Do not create files with only comments or documentation

## Verification Checklist
Before marking a file complete:
- [ ] File contains functional implementation (not just signatures)
- [ ] All TODO/FIXME/TBD/WIP markers removed
- [ ] File passes linting and type checking
- [ ] File has appropriate tests (if applicable)
- [ ] File follows project conventions and patterns
- [ ] File can be imported/used without errors
- [ ] File includes necessary error handling

## Examples of What NOT to Create
```
// ❌ Stub - Reject
function processPayment() {
    // TODO: implement
}

// ❌ Placeholder - Reject  
class PaymentProcessor {
    // TODO: add methods
}

// ❌ Incomplete - Reject
export const config = {
    // apiKey: process.env.API_KEY, // TODO: add
};
```

## Examples of What TO Create
```javascript
// ✅ Complete implementation
async function processPayment(amount, currency, recipient) {
    if (!amount || amount <= 0) {
        throw new ValidationError('Amount must be positive');
    }
    
    try {
        const transaction = await paymentGateway.charge({
            amount,
            currency,
            recipient: recipient.email
        });
        
        await auditLog.record('payment_processed', {
            transactionId: transaction.id,
            amount,
            currency,
            recipientId: recipient.id
        });
        
        return transaction;
    } catch (error) {
        await auditLog.record('payment_failed', {
            error: error.message,
            amount,
            currency,
            recipientId: recipient.id
        });
        throw error;
    }
}
```

## Relation to Enterprise Organization
This principle enforces:
- Zero-Placeholder Code Policy
- Rigorous Self-Validation 
- Todo-Driven Task Validation
- Append-Only CHANGELOG.md (requires actual work to log)
- Phase-tagged workflow (phases cannot complete with stubs)

## References
- [Zero-Placeholder Policy](references/zero-placeholder.md)
- [Todo Validation Protocol](references/todo-validation.md)
- [Self-Validation Framework](references/self-validation.md)
- [Rigorous Self-Validation section in SKILL.md](#rigorous-self-validation)