"""Check the reference vectors against Qiskit.

1. reference_vectors.json: builds each round as ryy(γ) · (u_you ⊗ u_them) ·
   ryy(−γ) and compares exact statevector probabilities.
2. native_vectors.json (written by `dart run bin/export_native.dart`): the
   same rounds compiled to IQM native gates. Rebuilds them with Qiskit's
   RGate, which has the same definition as IQM's prx, and CZ.

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


def native_probs(ops):
    from qiskit.circuit.library import RGate

    qc = QuantumCircuit(2)
    for op in ops:
        if op["name"] == "prx":
            qc.append(RGate(op["angle"], op["phase"]), [op["qubits"][0]])
        elif op["name"] == "cz":
            qc.cz(*op["qubits"])
    sv = Statevector.from_instruction(qc).probabilities_dict()
    out = [0.0] * 4
    for key, value in sv.items():
        them_bit, you_bit = int(key[0]), int(key[1])
        out[2 * you_bit + them_bit] = value
    return out


def main():
    here = pathlib.Path(__file__).parent
    cases = json.loads((here / "reference_vectors.json").read_text())
    worst = 0.0
    for c in cases:
        got = probs(dials(c["you"]), dials(c["them"]), c["f"])
        worst = max(worst, max(abs(g - e) for g, e in zip(got, c["p"])))
    print(f"{len(cases)} reference cases, max deviation {worst:.2e}")

    native_path = here / "native_vectors.json"
    if native_path.exists():
        native = json.loads(native_path.read_text())
        worst_native = 0.0
        for c in native:
            got = native_probs(c["ops"])
            worst_native = max(worst_native, max(abs(g - e) for g, e in zip(got, c["p"])))
        print(f"{len(native)} native-gate cases, max deviation {worst_native:.2e}")
        worst = max(worst, worst_native)
    sys.exit(0 if worst < 1e-9 else 1)


if __name__ == "__main__":
    main()
