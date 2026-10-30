"""Compatibility entry point for the stronger Levian integrity regression."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('levian_binding_integrity.py')),run_name='__main__')
