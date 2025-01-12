# Migration Guide: SimpleAMM V1 to V2

## Overview

This guide outlines the process for upgrading SimpleAMM from V1 to V2.

### Key Changes in V2

- Fee management moved from constant to configurable storage
- Added version control
- Enhanced error handling

## Prerequisites

1. Set up environment variables in `.env`:

```bash
# Deployment accounts
PRIVATE_KEY=xxx
ADMIN=0x...
OPERATORS=["0x123","0x456","0x789"]
EMERGENCY_ADMINS=["0xabc","0xdef"]
MULTISIG=0x...
STORAGE_ADDRESS=0x...
V1_IMPLEMENTATION=0x...
V2_IMPLEMENTATION=0x...

# Contract addresses
STORAGE_ADDRESS=0x...  # Existing EternalStorage address
```

## Migration Steps

### 1. Deploy V2 Implementation

```bash
forge script scripts/migration/01_DeployV2.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify

# Save the deployed address to .env
V2_IMPLEMENTATION=0x...
```

### 2. Upgrade to V2

```bash
forge script scripts/migration/02_UpgradeToV2.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

### 3. Verify Upgrade

- Check logic contract address in EternalStorage
- Verify version returns "2.0.0"
- Test fee configuration functionality

### 4. Unpause V2

```bash
forge script scripts/migration/03_UnpauseV2.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

### Emergency Rollback (if needed)

```bash
# Add previous implementation to .env
V1_IMPLEMENTATION=0x...

forge script scripts/migration/Rollback.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

## Post-Migration Tasks

1. Configure initial fee through operator role
2. Update frontend to support dynamic fee
3. Monitor system behavior
4. Update documentation

## Security Considerations

1. Ensure admin access is properly configured
2. Verify all roles are correctly assigned
3. Test fee management functionality thoroughly
4. Monitor initial transactions after upgrade
5. Have rollback procedure ready

## Verification Checklist

- [ ] V2 contract deployed successfully
- [ ] V1 contract paused
- [ ] Storage contract upgraded to point to V2
- [ ] V2 contract initialized with multisig
- [ ] V2 contract executor set to multisig
- [ ] All existing pools accessible
- [ ] Fee configuration working
- [ ] All roles maintained
- [ ] Frontend updated
- [ ] Documentation updated
- [ ] V2 contract unpaused

## Timeline

1. T+0: Deploy V2 implementation
2. T+1: Verify deployment
3. T+2: Execute upgrade
4. T+3: Verify upgrade
5. T+4: Checkings
6. T+5: Unpause V2
7. T+6: Announce completion

## Support

For any issues during migration, contact the development team:

- Emergency Support: emergency PICs