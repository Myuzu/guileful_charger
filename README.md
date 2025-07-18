# GuilefulCharger

This project implements a simplified billing system, focusing on core functionalities while omitting certain complexities for the sake of time and scope.

## Scope Limitations

For the sake of time, the following crucial concepts have been intentionally omitted or simplified:

*   **Currency:** Only a single currency is supported.
*   **Taxation:** No handling for taxation.
*   **Subscription Plans:** Subscriptions are always in an auto-renew state, and there are no distinct plans.
*   **User Cancellation:** No user-initiated subscription cancellation.
*   **Subscription Dates:** Subscriptions do not have explicit start/end dates.
*   **Payment Methods:** Only one payment method is supported per customer, which is always active and sensitive fields are not encrypted.
*   **Refunds:** No refund logic is implemented.

## Architectural Considerations

*   **Concurrency:** Utilizes PostgreSQL pessimistic locks for concurrent operations.
*   **Message Delivery:** Ensures exactly-once delivery guarantee for critical operations.

### PostgreSQL Setup (Zero RPO)

The PostgreSQL setup is designed for zero Recovery Point Objective (RPO):

*   **1 Primary Node:** The main database server.
*   **1 Synchronous Standby:** For immediate failover, ensuring no data loss.
*   **1-2 Asynchronous Standbys:** Used for reporting, analytics, and non-critical read operations.

## Core Entities

### Customer

*   **CustomerID:** Unique identifier.
*   **Name:** Customer's name.
*   **Email:** Primary contact email.
*   **BillingAddress:** Address for billing purposes.
*   **PaymentMethodId:** Associated payment method.
*   **CreatedAt:** Account creation timestamp.
*   **UpdatedAt:** Last update timestamp.

### Subscription

*   **SubscriptionID:** Unique identifier.
*   **CustomerID:** Reference to Customer.
*   **Amount:** Base subscription price.
*   **Status:** `active`, `paused`, `cancelled`, `past_due`.
*   **BillingCycle:** Current billing cycle number.
*   **NextBillingAt:** Date of next billing.
*   **CreatedAt:** Account creation timestamp.
*   **UpdatedAt:** Last update timestamp.

### Invoice

*   **InvoiceID:** Unique identifier.
*   **CustomerID:** Reference to Customer.
*   **SubscriptionID:** Reference to Subscription.
*   **Amount:** Total amount.
*   **Status:** `Draft`, `Issued`, `Paid`, `Void`, `Past_Due`.
*   **DueDate:** Payment due date.
*   **IssuedAt:** When invoice was issued.
*   **PaidAt:** When invoice was paid.
*   **BillingPeriod:** Start and end dates for billing period.
*   **CreatedAt:** Account creation timestamp.

### Payment

*   **PaymentID:** Unique identifier.
*   **InvoiceID:** Reference to Invoice.
*   **CustomerID:** Reference to Customer.
*   **Amount:** Payment amount.
*   **Status:** `pending`, `completed`, `failed`.
*   **TransactionID:** External payment processor transaction ID.
*   **PaidAt:** When payment was processed.
*   **FailureReason:** Description of failure.
*   **CreatedAt:** Account creation timestamp.

### PaymentMethod

*   **PaymentMethodID:** Unique identifier.
*   **CustomerID:** Reference to Customer.
*   **Name:** PaymentMethod's name.
*   **LastUsedAt:** When method was last used.
*   **FailureCount:** Number of payment failures.
*   **CreatedAt:** Account creation timestamp.
*   **UpdatedAt:** Last update timestamp.

### AuditLog

*   **LogID:** Unique identifier.
*   **EntityType:** Type of entity (`Subscription`, `Payment`, `Invoice`).
*   **EntityID:** ID of the affected entity.
*   **Action:** `Created`, `Updated`, `Deleted`, `Status Change`.
*   **Changes:** What was changed.
*   **CreatedAt:** When change occurred.

### RebillingStrategy

*   **MaxRetries:** Maximum number of retry attempts.
*   **RetryIntervals:** Array of intervals between retries.
*   **FailureActions:** Actions to take on failure.
*   **NotificationRules:** When to notify customer/admin.
*   **GracePeriod:** Additional time before subscription suspension.
*   **EscalationRules:** When to escalate failed payments.

## Relationships

### Primary Relationships

*   **Customer** -> **Subscriptions** (1:N)
*   **Subscription** -> **Invoices** (1:N)
*   **Invoice** -> **Payments** (1:N)
*   **Customer** -> **PaymentMethods** (1:1)

### Secondary Relationships

*   **Payment** -> **PaymentMethod** (N:1)
*   **Invoice** -> **AuditLog** (1:N)
*   **Subscription** -> **AuditLog** (1:N)
*   **Payment** -> **AuditLog** (1:N)

## Main Rebilling Logic

The rebilling process follows these steps:

1.  **Initial Attempt:** First, try to charge the full subscription amount.
2.  **Partial Charges (if insufficient funds):** If the bank responds with "insufficient funds," attempt to charge partial amounts in sequence:
    *   75% of the original amount.
    *   50% of the original amount.
    *   25% of the original amount.
3.  **Attempt Limit:** A maximum of 4 attempts is allowed for each rebill after a successful payment.

## Getting Started

To set up and run the GuilefulCharger project locally, follow these steps:

### Prerequisites

*   Ruby (version specified in `.ruby-version`)
*   Bundler
*   Docker and Docker Compose (for database and other services)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-repo/guileful_charger.git
    cd guileful_charger
    ```

2.  **Install Ruby dependencies:**
    ```bash
    bundle install
    ```

3.  **Set up Docker services:**
    ```bash
    make bootstrap
    make docker-compose-up-test
    ```

4.  **Prepare the database:**
    ```bash
    make db-test-prepare
    ```

### Running Tests

To run the project's tests, use the following commands:

*   **Run all tests:**
    ```bash
    make test
    ```
*   **Run a single test file:**
    ```bash
    make test spec/models/customer_spec.rb # Example
    ```

### Linting and Security Scan

*   **Run Linter (RuboCop):**
    ```bash
    bin/rubocop
    ```
*   **Run Security Scan (Brakeman):**
    ```bash
    bin/brakeman
    ```
