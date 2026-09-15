import sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from engine import normalize_markdown
class MarkdownTests(unittest.TestCase):
    def test_latex_contents_and_number(self):
        body = r'\begin{pmatrix}a & b\\ c & d\end{pmatrix}  \tag{12}'
        self.assertEqual(normalize_markdown(r'\[ '+body+r' \]'), '$$\n'+body+'\n$$\n')
    def test_inline_and_bullets(self):
        self.assertEqual(normalize_markdown('• Given $ x_{i}  + \\alpha $\n• Next'), '- Given $x_{i}  + \\alpha$\n- Next\n')
    def test_escaped_dollar(self):
        self.assertEqual(normalize_markdown(r'Cost \$5. Let \(x^2\).'), 'Cost \\$5. Let $x^2$.\n')
    def test_math_marker_not_bullet(self):
        self.assertEqual(normalize_markdown('$$\n• x\n$$'), '$$\n• x\n$$\n')
if __name__=='__main__': unittest.main()
