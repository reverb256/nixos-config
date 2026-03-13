---
name: require-deployment-success
enabled: true
event: bash
pattern: (just deploy|just switch)
severity: block
message: |
  ## Deployment Result

  %OUTPUT%

  If failed: fix the error before deploying again.
  If succeeded: you're good to go.
