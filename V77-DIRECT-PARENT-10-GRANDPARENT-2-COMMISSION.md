# Royal Alliance V77 — Direct-parent 10%, grandparent 2%

## Intended commission rule
- On an approved payment, the direct parent profile (Agent or Sub-Agent) receives 10%.
- The parent of that direct parent (Agent or Sub-Agent) receives 2%, if that profile exists.
- If the collector has no parent, the collector receives 10%.
- Member referral income remains a separate 2% earning and continues to follow the existing two-valid-referrals condition.
- No other ancestor receives a hierarchy override.
- Existing records are not modified by this migration; it changes the approval function for future approvals only.

## Example for a ₹2,000 approved payment
| Beneficiary | Rate | Amount |
|---|---:|---:|
| Direct parent | 10% | ₹200 |
| Parent's parent | 2% | ₹40 |
| Total hierarchy commission | 12% | ₹240 |

Member-referral income, when eligible, is separate and is not included in the ₹240.

## Important deployment note
This migration is packaged but has **not** been applied to live Supabase as part of this ZIP delivery. Review the company-approved commission scheme, back up the database, apply the migration in the intended environment, then verify with authenticated end-to-end tests. It does not create demo members/payments. Do not mark synthetic payments as real collections.
