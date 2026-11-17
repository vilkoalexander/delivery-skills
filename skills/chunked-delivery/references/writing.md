# Writing: Simplified Technical English

The default for all text that a person reads in a run: questions, the chunk
list, reports, findings, rulings, code comments, documents and text for a
commit or a pull request. The source is ASD-STE100. `"writing": "free"` in
`docs/review/delivery.json` sets these rules off.

## Words

- Use one word for one thing. Use the same word each time.
- Use the short, common word: `use`, not `utilize`. `start`, not `initiate`.
  `do`, not `perform`.
- Use a word as one part of speech. If `test` is a noun in the text, write
  `do a test`, not `test the change`.
- Write a noun cluster of three words at most. Put `of` or `for` in a longer one.
- Do not use idioms, slang or figures of speech.
- Keep the articles: `the`, `a`, `an`.

## Sentences

- An instruction has 20 words at most. A description has 25 words at most.
- Put one instruction in one sentence. Put one topic in one sentence.
- Write an instruction as a command: `Run the gate.`
- Put the condition first: `If the gate fails, send the output to the implementer.`
- Use the active voice. Name who or what does the action.
- Use the simple present, the simple past or the simple future.
- Do not use an `-ing` word as a verb. Write `the gate runs`, not `the gate is running`.
- Do not use `should`, `might` or `could` for a fact or an instruction. Write what is true and what to do.
- Use a vertical list for three or more items.

## Paragraphs

- A paragraph has one topic and six sentences at most.
- The first sentence says what the paragraph is about.
- Start a warning with the command or the condition, then give the result.

## What these rules do not change

- Code, identifiers, commands, paths and the output of tools.
- Text that you quote from a person or from a file.
- The field labels and the shape of the report formats.
- Names that the project uses for its own things. These are technical names.

The specification also has a dictionary of approved words. This file holds
only the rules for sentences. If the project has the dictionary, the
dictionary decides.
