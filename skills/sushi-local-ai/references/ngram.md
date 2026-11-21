# Conditional Qwen n-gram optimization

Sources: the “Choosing the n-gram table” sections on [2bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-2bpw#choosing-the-n-gram-table), [2.6bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-2.6bpw#choosing-the-n-gram-table), [3bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-3bpw#choosing-the-n-gram-table), and [4bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-4bpw#choosing-the-n-gram-table), checked 2026-10-27.

| Variant | Disk | Config entry |
|---|---:|---|
| 4-bit affine | 29.8 GiB | `{"file":"ngram_table.bin","bits":4,"group_size":32}` |
| bf16 | 95.4 GiB | `{"file":"ngram_table.bin","bits":16,"group_size":0}` |

These tables are SSD-resident; changing them does not reduce GPU weight memory. bf16 trades roughly 66 GiB extra disk for a modest measured quality improvement. Do not promise a specific gain on 2bpw or STQ from measurements on another pack. 2/2.6/3bpw ship 4-bit; 4bpw ships bf16. The linked cards explicitly support interchange among those EXL3 Qwen variants. STQ ships 4-bit but needs separate current compatibility confirmation; MiMo/GLM/DeepSeek are outside this procedure.

## Decide before downloading

1. Resolve the actual pack directory and identify it from its config and model metadata, not only its folder name.
2. Read `config.json` → `ngram_table`, then inspect the referenced file's presence, size and, where available, Hugging Face hash. Bits/group metadata alone does not prove the file matches. If metadata and file disagree, repair or restore before launch.
3. If the desired variant is already complete and matching, report **already configured** and skip download/edit. Ask about quality-versus-disk only when not established by the user's request. A 4-bit pack on a disk-constrained Mac needs no change; a bf16 pack already selected for quality needs no change.
4. Plan free space for the entire new table while retaining the old one for rollback, plus any CLI cache/temp duplication. The net 66 GiB increase is not the peak download requirement. Use the actual target volume.

## Applying an authorized change

Stop this model's server before modifying either file. Save the original JSON and keep the old table until validation. Download into a **separate staging directory on the same volume**, never directly over the live table:

```sh
# bf16 source
hf download beamster/Qwen3.8-Flash-Next-Sushi-4bpw ngram_table.bin --local-dir <staging-directory>
# OR 4-bit source, explicitly documented by the 4bpw card
hf download beamster/Qwen3.8-Flash-Next-Sushi-3bpw ngram_table.bin --local-dir <staging-directory>
```

Substitute real quoted paths, use only the chosen command, verify completion and source metadata/hash, then move the old table to a unique backup and the new one into the configured location. Update only the `ngram_table` object with a JSON-aware tool, preserving all unrelated fields. Replace JSON through a temporary file/rename. The table+JSON pair is not a single atomic operation: keep the server stopped until both agree, and restore both on any failure. Do not leave stale config pointing at a different precision.

Restart and test generation; retain rollback until successful. Document the customized file: a later `hf download` of the full original pack can restore its original table/config, and `sushi pull` checks listing sizes. Recheck the pair after updates. Cleanup of large backups is a separate deliberate action, not a hidden side effect of the recommendation.
