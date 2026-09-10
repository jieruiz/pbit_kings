"""Topology, transaction image, schedule and certificate regression tests."""
import argparse
import ast
import csv
import re
import tempfile
import unittest
from pathlib import Path
import gen_chimera_problem as g


class GeneratorTests(unittest.TestCase):
    def test_topology(self):
        edges = list(g.all_edges())
        self.assertEqual(len(edges), 9440)
        self.assertEqual(len(set(g.edge_address(*e) for e in edges)), len(edges))
        degree = [0] * g.N
        for a, b in edges:
            degree[a] += 1
            degree[b] += 1
            color = lambda v: ((v // 8 // 20) + (v // 8 % 20) + (v % 8 // 4)) % 2
            self.assertNotEqual(color(a), color(b))
        self.assertEqual(max(degree), 6)
        for e in [(0, 1), (4, 20), (0, 161), (159, 167), (-1, 4)]:
            with self.assertRaises(ValueError):
                g.edge_address(*e)

    def test_table_matches_rtl(self):
        rtl = (g.HERE.parents[1] / "new_version" / "tanh_LUT.sv").read_text()
        h1 = rtl.split("3'd1: begin", 1)[1].split("3'd2: begin", 1)[0]
        values = {int(i): int(v, 16) for i, v in re.findall(r"5'd(\d+): tanh_pos_thr = 16'h([0-9A-F]+)", h1)}
        with (g.HERE / "inputs" / "anneal_i0_32_dec.txt").open() as f:
            table = list(csv.DictReader(f))
        self.assertEqual(len(values), 32)
        for row in table:
            self.assertEqual(values[int(row["level"])], int(row["h=1"]))

    def test_seeds(self):
        seeds, spins = g.initial_state(0)
        self.assertEqual(len(set(seeds)), 1600)
        self.assertTrue(all(0 < v < 2**32 for v in seeds))
        self.assertEqual(len(spins), 3200)
        self.assertEqual((seeds, spins), g.initial_state(0))
        self.assertNotEqual((seeds, spins), g.initial_state(1))

    def test_all_cases(self):
        with tempfile.TemporaryDirectory() as tmp:
            for case in g.CASES:
                args = argparse.Namespace(case=case, output=str(Path(tmp) / case),
                    sweeps=200, runs=1, majority=5, seed_master=2461, init_seed=314592,
                    schedule="linear", i0_start=0.1, i0_end=4.0)
                manifest = g.generate(args)
                self.assertEqual(sum(s["sweeps"] for s in manifest["stages"]), 200)
                program = [int(v, 16) for v in (Path(args.output) / "config_0.mem").read_text().split()]
                p, chains, h, couplings, scale, quant, target = g.load_case(case)
                unit, node, edge, seed, payload = 0, 0, 0, 0, {}
                got_edges, got_nodes, got_seeds = {}, {}, {}
                for instruction in program:
                    op, addr, value = instruction >> 48, (instruction >> 32) & 0xffff, instruction & 0xffffffff
                    if op != 1:
                        continue
                    if addr == 0x74: unit = ((value & 255) * 20 + (value >> 8))
                    elif addr == 0x78: node = (value & 3) + 4 * ((value >> 8) & 1)
                    elif addr == 0x88: seed = value
                    elif addr == 0x98: edge = value
                    elif addr in (0x7c, 0x8c, 0x9c): payload[addr] = value
                    elif addr == 0x80: got_nodes[unit * 8 + node] = payload[0x7c]
                    elif addr == 0x90: got_seeds[unit * 4 + seed] = payload[0x8c]
                    elif addr == 0xa0:
                        key = (unit // 20, unit % 20, edge & 7, edge >> 8)
                        self.assertNotIn(key, got_edges)
                        got_edges[key] = payload[0x9c]
                seeds, spins = g.initial_state(0)
                self.assertEqual([got_seeds[i] for i in range(1600)], seeds)
                self.assertEqual(len(got_nodes), g.N)
                for v in range(g.N):
                    self.assertEqual(got_nodes[v], 7 | (spins[v] << 8) | (int(h[v] < 0) << 11) | (quant(h[v]) << 12))
                self.assertEqual(len(got_edges), 9440)
                for a, b in g.all_edges():
                    value = couplings.get((a, b), 0)
                    encoded = got_edges[g.edge_address(a, b)]
                    self.assertEqual(encoded >> 2, quant(value))
                    self.assertEqual((encoded >> 1) & 1, int(value < 0))
                    self.assertEqual(encoded & 1, int(quant(value) > 0))

    def test_python36_syntax(self):
        for path in g.HERE.glob("*.py"):
            # On Python 3.8+ the parser can explicitly reject newer syntax.
            try:
                ast.parse(path.read_text(), feature_version=(3, 6))
            except TypeError:
                ast.parse(path.read_text())


if __name__ == "__main__":
    unittest.main()
