"""Check reference_vectors.json against Qiskit.

Builds each round as ryy(γ) · (u_you ⊗ u_them) · ryy(−γ) and compares the
exact statevector probabilities with the stored vectors. Run with:

    pip install qiskit
    python test/qiskit_check.py
"""
import json
import math
import pathlib
import sys

from qiskit import QuantumCircuit
from qiskit.quantum_info import Statevector

PRESETS = {
    "hold": (0, 0, 0),
    "lance": (math.pi, 0, 0),
    "conjugate": (0, math.pi / 2, 0),
    "phaseLance": (math.pi, 0, math.pi / 2),
}


def dials(side):
    if "preset" in side:
        return PRESETS[side["preset"]]
    t, p, a = side["deg"]
    return (math.radians(t), math.radians(p), math.radians(a))


def probs(you, them, fidelity):
    gamma = fidelity * math.pi / 2
    qc = QuantumCircuit(2)
    qc.ryy(gamma, 0, 1)
    for qubit, (t, p, a) in ((0, you), (1, them)):
        qc.u(t, math.pi - a - p, math.pi + a - p, qubit)
    qc.ryy(-gamma, 0, 1)
    sv = Statevector.from_instruction(qc).probabilities_dict()
    # Qiskit keys read "them, you"; the game indexes 2 * you + them.
    out = [0.0] * 4
    for key, value in sv.items():
        them_bit, you_bit = int(key[0]), int(key[1])
        out[2 * you_bit + them_bit] = value
    return out


def main():
    path = pathlib.Path(__file__).with_name("reference_vectors.json")
    cases = json.loads(path.read_text())
    worst = 0.0
    for c in cases:
        got = probs(dials(c["you"]), dials(c["them"]), c["f"])
        worst = max(worst, max(abs(g - e) for g, e in zip(got, c["p"])))
    print(f"{len(cases)} cases, max deviation {worst:.2e}")
    sys.exit(0 if worst < 1e-9 else 1)


if __name__ == "__main__":
    main()
