/**
 * AI Agent Activity Monitor - Starter Implementation
 * 
 * Logs all agent actions to immutable storage with alerting on suspicious patterns.
 * Customize for your organization's security requirements.
 */

const winston = require('winston');
const crypto = require('crypto');

// Create immutable logger (configure for S3, write-once DB, or append-only file)
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'ISO8601' }),
    winston.format.json()
  ),
  defaultMeta: { 
    service: 'agent-monitor',
    sessionId: crypto.randomUUID()
  },
  transports: [
    // In production: replace with S3 transport, Kafka, or write-once DB
    new winston.transports.File({ 
      filename: 'logs/agent-actions.log',
      maxsize: 10485760, // 10MB
      maxFiles: 5
    })
  ]
});

class AgentMonitor {
  constructor(options = {}) {
    this.sessionId = crypto.randomUUID();
    this.actionCount = 0;
    this.failureCount = 0;
    this.startTime = Date.now();
    this.maxActionsPerSession = options.maxActionsPerSession || 100;
    this.failureThreshold = options.failureThreshold || 5;
    this.highRiskActions = options.highRiskActions || [
      'deploy', 'delete', 'export_data', 'modify_prod', 'access_credentials'
    ];
  }

  async logAction(action) {
    this.actionCount++;
    
    const logEntry = {
      event: 'agent:action',
      sessionId: this.sessionId,
      timestamp: new Date().toISOString(),
      action: action.type,
      target: action.target,
      metadata: action.metadata,
      sessionStats: {
        totalActions: this.actionCount,
        failures: this.failureCount,
        duration: Date.now() - this.startTime
      }
    };

    logger.info('agent:action', logEntry);

    // Check for high-risk actions requiring human approval
    if (this.highRiskActions.includes(action.type)) {
      logger.warn('agent:high_risk_action', {
        ...logEntry,
        alert: 'REQUIRES_HUMAN_APPROVAL'
      });
      
      // TODO: Integrate with your approval system (Slack, PagerDuty, email)
      console.warn(`⚠️  High-risk action detected: ${action.type}`);
      console.warn('   Action paused pending human approval.');
      
      return { approved: false, reason: 'requires_human_approval' };
    }

    // Rate limiting check
    if (this.actionCount > this.maxActionsPerSession) {
      logger.error('agent:rate_limit_exceeded', logEntry);
      throw new Error('Session action limit exceeded');
    }

    return { approved: true };
  }

  async logFailure(error, action) {
    this.failureCount++;
    
    logger.error('agent:failure', {
      event: 'agent:failure',
      sessionId: this.sessionId,
      timestamp: new Date().toISOString(),
      error: error.message,
      action: action?.type,
      failureCount: this.failureCount
    });

    // Circuit breaker: stop after threshold failures
    if (this.failureCount >= this.failureThreshold) {
      logger.crit('agent:circuit_breaker_trip', {
        reason: 'failure_threshold_exceeded',
        failureCount: this.failureCount
      });
      
      throw new Error('Circuit breaker tripped: too many failures');
    }
  }

  getSessionSummary() {
    return {
      sessionId: this.sessionId,
      startTime: new Date(this.startTime).toISOString(),
      duration: Date.now() - this.startTime,
      totalActions: this.actionCount,
      failures: this.failureCount,
      status: this.failureCount >= this.failureThreshold ? 'CIRCUIT_OPEN' : 'ACTIVE'
    };
  }
}

// Example usage
async function main() {
  const monitor = new AgentMonitor({
    maxActionsPerSession: 100,
    failureThreshold: 5
  });

  console.log('🔒 Agent Monitor Started');
  console.log(`   Session ID: ${monitor.sessionId}`);
  console.log(`   Max actions/session: ${100}`);
  console.log(`   Failure threshold: ${5}`);
  console.log('');

  // Simulate agent actions
  try {
    await monitor.logAction({
      type: 'read_file',
      target: '/app/config.json',
      metadata: { size: 2048 }
    });

    await monitor.logAction({
      type: 'api_call',
      target: 'https://api.example.com/data',
      metadata: { method: 'GET', status: 200 }
    });

    // This will trigger human approval requirement
    await monitor.logAction({
      type: 'deploy',
      target: 'production',
      metadata: { service: 'web-api', version: 'v2.1.0' }
    });

  } catch (error) {
    await monitor.logFailure(error, { type: 'unknown' });
    console.error('❌ Monitor error:', error.message);
  }

  console.log('');
  console.log('📊 Session Summary:');
  console.log(monitor.getSessionSummary());
}

// Run if executed directly
if (require.main === module) {
  main().catch(console.error);
}

module.exports = { AgentMonitor };
