# Buenos Aires Content Pipeline Fixture

Use this fixture to validate the OnlyMacs plan-file parser and JSON artifact checks without depending on a private content repository.

learnerLocales: en de fr it ko

Keep every lemma unique. Avoid vulgarity and slang traps such as concha, coger, boludo, mina, quilombo, garcha, pelotudo, and forro.

## Step 1: Define the pack structure

Output: `setDefinitions.json`

Create the set definition file for the Buenos Aires Spanish beginner pack. Include vocab groups `es-bue-vocab-beg-01` and `es-bue-vocab-beg-02`, sentence groups `es-bue-sent-01` and `es-bue-sent-02`, lesson group `es-bue-lesson-01`, and an alphabet module.

## Step 2: Generate vocabulary groups

Output: `vocab-groups-01-02.json`

Create exactly 40 vocabulary items for groups 01-02. Each item should include stable ids, localized notes, and enough metadata for downstream lesson generation.

## Step 3: Generate sentence groups

Output: `sentences-groups-01-02.json`

Create exactly 40 sentence items for groups 01-02. Each item should include stable ids, source text, translation fields, and tags that connect back to the pack structure.

## Step 4: Generate lesson groups

Output: `lessons-groups-01-02.json`

Create exactly 2 lesson objects for groups 01-02. Keep the result as one small JSON file.

## Step 5: Generate alphabet cards

Output: `alphabet.json`

Create 12-16 cards for the alphabet module. Each phonics card must include pronunciationFeatures, example text, translations, and script metadata.
