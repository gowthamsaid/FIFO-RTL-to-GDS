# Generic Yosys Synthesis Results

## Design
Parameterized synchronous FIFO

Configurations:
- 8-bit width, 16-entry depth
- 32-bit width, 32-entry depth

## Tool
Yosys 0.52 - generic synthesis

## Results

| Metric | 8x16 | 32x32 |
|---|---:|---:|
| Storage bits | 128 | 1024 |
| Total flip-flops | 149 | 1072 |
| Multiplexers | 120 | 992 |
| Other logic gates | 86 | 142 |
| Total generic cells | 355 | 2206 |
| Structural check | PASS | PASS |

## Findings

1. Data storage increases by 8x between configurations.
2. Both memory arrays were mapped into flip-flop-based storage.
3. The 8x16 design contains 128 memory flip-flops.
4. The 32x32 design contains 1024 memory flip-flops.
5. Read selection uses 120 and 992 two-input multiplexers.
6. Control logic grows more slowly than storage and read logic.
7. Both synthesized designs passed Yosys structural checks.

## Limitations

These results represent generic logic synthesis.

They do not represent technology-mapped standard-cell area,
physical routing, clock tree synthesis, or timing closure.

Physical implementation results will be added after OpenROAD.
