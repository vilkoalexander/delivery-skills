# Risk from the diff content

Read when `risk.sh` ends with `escalators: jev`, or to change its settings.

## When it runs

`risk.sh` sends the hunks through `delivery-pipeline/scripts/risk-content.sh`
when `TYPESAFE_API_KEY` is set. That script asks the Jev model of TypeSafe the
escalators as yes or no questions, for each changed file:

- Did a signature change?
- Does a caller see a change?
- Is this the path of production data?
- Does it delete data?
- Does it touch auth or money?

Each file costs approximately one hundred milliseconds and a fraction of a
cent. The answer is the same on each run.

## How it sets the class

- Each file starts from the class of its path. The pass does not lower a
  class.
- Data, auth or money: high.
- Signature or caller: one class up.
- A new file skips the signature question and the caller question.
- A probability between `RISK_P_UNSURE` (0.5) and `RISK_P_ACT` (0.7) gives an
  `unsure:` line and holds the file at medium. This occurs only when a yes can
  raise the class.

Put each `unsure:` line into the chunk list at the approval of the plan. The
human decides it. Apart from these lines, the class is final.

## When it does not run

The last line is `escalators: controller` when there is no key, when
`RISK_CONTENT=off`, or when the content pass failed. Then examine the escalators
in `references/plan.md` yourself.

## Settings

- `RISK_DIFF_RANGE=base..head` aims the content pass at a range and not at
  the working tree.
- `bash delivery-pipeline/scripts/risk-content.test.sh` examines the two
  scripts against a fake endpoint. It needs no key.
