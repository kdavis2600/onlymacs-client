# OnlyMacs Ops Notes

## Website redemption codes

Website/package redemption codes must follow the seeded two-word convention:

- `PREFIX-SUFFIX`, for example `MINT-CODE` or `FIG-DESK`
- prefix from `MINT FIG MAC SWIFT SPARK NOVA BYTE PIXEL ORBIT LOCAL`
- suffix from `APPLE DESK BUILD FOCUS PILOT ATLAS BRIDGE RIVER CLOUD CODE`

Do not create date-stamped or internal-looking codes such as `OM-APR30-8`.
Use `scripts/set-onlymacs-redemption-code.sh` so the convention is validated before the live invite store is changed.
