# GuilefulCharger

For the sake of time some crucial concepts was omited, such as:
- currency will always be UAH
- no taxation handling
- Subscribtion will always be in auto-renew state and there are no Plans
- no user-initiated Subscribtion canceleation
- no alternative Payment collection methods: only one PaymentMethod, it will be always active without encryption on sensative fields
- skip on refunds logic

## Core entities

- Customer

CustomerID: Unique identifier
Name: Customer's name
Email: Primary contact email
Status: Active/Inactive
BillingAddress: Address for billing purposes
PaymentMethodId: associated payment method
TaxInformation: Tax-related details
CreatedAt: Account creation timestamp
UpdatedAt: Last update timestamp

- Subscription

SubscriptionID: Unique identifier
CustomerID: Reference to Customer
Amount: Base subscription price
Status: Active/Paused/Cancelled/Past_Due
StartDate: When subscription begins
EndDate: When subscription ends (if applicable)
BillingCycle: Current billing cycle number
NextBillingDate: Date of next billing
CancellationDate: When subscription was/will be cancelled
CreatedAt: Account creation timestamp
UpdatedAt: Last update timestamp

- Invoice

InvoiceID: Unique identifier
CustomerID: Reference to Customer
SubscriptionID: Reference to Subscription
Amount: Total amount
Currency: Invoice currency
Status: Draft/Issued/Paid/Void/Past_Due
DueDate: Payment due date
IssueDate: When invoice was issued
PaidDate: When invoice was paid
BillingPeriod: Start and end dates for billing period
CreatedAt: Account creation timestamp

- Payment

PaymentID: Unique identifier
InvoiceID: Reference to Invoice
CustomerID: Reference to Customer
Amount: Payment amount
Status: Pending/Completed/Failed
TransactionID: External payment processor transaction ID
PaymentDate: When payment was processed
FailureReason: Description of failure (if applicable)
Metadata: Additional payment-specific data
CreatedAt: Account creation timestamp

- PaymentMethod

PaymentMethodID: Unique identifier
CustomerID: Reference to Customer
Details: Encrypted payment details
LastUsedDate: When method was last used
FailureCount: Number of payment failures
CreatedAt: Account creation timestamp
UpdatedAt: Last update timestamp

- AuditLog

LogID: Unique identifier
EntityType: Type of entity (Subscription/Payment/Invoice)
EntityID: ID of the affected entity
Action: Created/Updated/Deleted/Status Change
Changes: What was changed
CreatedAt: When change occurred

- RebillingStrategy

MaxRetries: Maximum number of retry attempts
RetryIntervals: Array of intervals between retries
FailureActions: Actions to take on failure
NotificationRules: When to notify customer/admin
GracePeriod: Additional time before subscription suspension
EscalationRules: When to escalate failed payments

### Relationships
Primary Relationships

Customer -> Subscriptions (1:N)
Subscription -> Invoices (1:N)
Invoice -> Payments (1:N)
Customer -> PaymentMethods (1:1)

Secondary Relationships

Payment -> PaymentMethod (N:1)
Invoice -> AuditLog (1:N)
Subscription -> AuditLog (1:N)
Payment -> AuditLog (1:N)


Main Rebilling Logic:
* First, try to charge the full subscription amount
* If the bank responds with "insufficient funds," attempt to charge 75%, 50%, and 25% of the amount
* A maximum of 4 attempts is allowed for each rebill after success payment
