"""Test anchors and ordinal selection on minimal synthetic upstream-shaped code."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ordinals', ROOT / 'scripts/patch_ordinals.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

MOCK = """#include <stdint.h>
static int u40x_find_gpu_pass(INTN enc) {
    for (k = 0; k < sizeof(fastL) / sizeof(fastL[0]); k++) {
       return 12;
    }
    for (b = 0; b < maxBus; b++) {
      for (d = 0; d < 32; d++) {
          if (valid) {
                    gBus = b; gDev = d; gFn = f;
                    return 1;
          }
      }
    }
    return 0;
}
static int u40x_find_gpu(void) { return 0; }
"""

class TestOrdinalPatch(unittest.TestCase):
    def test_first_selection(self):
        out = mod.generate(MOCK, 0)
        self.assertIn('if (match_index++ != 0u) continue;', out)
        self.assertIn('UINTN match_index = 0;', out)
        self.assertNotIn('for (k = 0;', out)
        self.assertEqual(out.count('gBus = b; gDev = d; gFn = f;'), 1)

    def test_second_selection(self):
        out = mod.generate(MOCK, 1)
        self.assertIn('if (match_index++ != 1u) continue;', out)
        self.assertNotIn('for (k = 0;', out)

    def test_mismatched_upstream_fails(self):
        with self.assertRaises(ValueError):
            mod.generate(MOCK.replace('gBus = b;', 'gBus = 0;'), 0)

if __name__ == '__main__':
    unittest.main()
