# NixOS Configuration Syntax Fix Plan

## Context

The NixOS flake is failing to evaluate due to syntax errors in the configuration modules. The error message indicates a syntax issue in `/data/@projects/infra/nixos/modules/networking.nix` at line 129.

## Problem Identified

The `networking.nix` module has a malformed structure where the `forward-zone` configuration is incomplete, causing a syntax error that prevents the entire flake from evaluating.

## Solution

Fix the incomplete `forward-zone` configuration in `modules/networking.nix` by properly closing the configuration block.

## Technical Details

The error occurs because the `forward-zone` configuration is missing proper closing braces and the configuration is malformed. The networking configuration needs to be properly structured with correct Nix syntax.

## Implementation Plan

1. **Fix networking.nix syntax** - Complete the malformed `forward-zone` configuration
2. **Verify all module syntax** - Check for any other syntax errors in the modules
3. **Test flake evaluation** - Run `nix flake check` to ensure the fix works
4. **Validate deployment** - Test that the configuration can be deployed to target hosts

## Files to Modify

- `/data/@projects/infra/nixos/modules/networking.nix` - Fix syntax error in forward-zone configuration

## Verification Steps

1. Run `nix flake check` to verify flake evaluation
2. Run `nix flake show` to verify all outputs are accessible
3. Test deployment to a single host to ensure configuration applies correctly

This fix will resolve the syntax error preventing the NixOS configuration from being evaluated and deployed.