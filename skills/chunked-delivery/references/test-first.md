# When the tests and the code do not agree

Read when an implementer stops with `BLOCKED` on a test, when a test of a
test author fails after the implementation, or when `test-first.sh` names a
file.

You decide which side is wrong. The plan is the authority, not the test and
not the code. Use the task text, the acceptance criteria, the `covers` lines
of the test author and the evidence of the implementer. Ask for the assertion
and the failure output as quoted text. Do not read the diff.

| You find | The decision | Do |
| --- | --- | --- |
| The test asserts what a criterion or the task text states | The code is wrong | Send the failure output to the implementer |
| The test asserts something that the plan does not state, or the opposite of what it states | The test is wrong | Send the quote to the test author, with a message to the same agent |
| The implementer changed a test file | The change is not valid, whichever side is wrong | Tell the implementer to put the file back. Then decide as in the two rows above |
| The plan does not say, and the two readings give different behaviour | The plan has a gap | A small gap is a ruling: decide, and send it to the two agents. If the decision changes an acceptance criterion, stop and ask the human |

- The implementer never edits a test. The test author never edits code.
- Write each decision on the `Rulings:` line: `tests wrong` or `code wrong`,
  the test name, and the line of the plan that decided it.
- A decision is a static round. Do two for each chunk at most. Then park the
  disagreement and put the two readings in the report.
- Before a test author changes a test again, run `test-first.sh open` again.
  After it, run `lock` again. Then the implementer continues.

## When `test-first.sh lock` names a file

A test author changed a file that is not a test. Tell that test author to put
the file back. If the file is a fixture or a test helper that the tests need,
and its path does not look like a test, name it in `TEST_FIRST_ALLOW` and run
`lock` again. Write the path on the `Rulings:` line.
