# Return quantity precision

New credit-note lines use the sale quantity range and precision. Accept values from 0.001 to 1,000,000 with up to three meaningful fractional digits, including trailing zeros. Blank or zero leaves a line unselected. Positive input must fit the quantity sold less active prior credit notes. Recheck this bound when posting.

Show the supported quantity without rounding a historical remainder up to the next return increment. For example, 0.0009995 remains in history but cannot be returned as 0.001. Preserve the original invoice and existing posted request identities. Web retries use the exact frozen request and key. Invalid edits remain editable and block credit-note submission.
