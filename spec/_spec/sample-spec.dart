
import '../_spec/jasmine.dart';

void main() {
  for (int i in [1, 2, 3]) {
    describe('foo sample ${i}', () {
      it('is cool', () {
        expect(true).toBe(true);
      });

      it('so cool', () {
        expect(false).toBe(true);
      });

      for (String str in ['foo', 'bar', 'baz']) {
        it('more ${str} cool', () {
          expect(true).toBe(true);
        });
      }
    });
  }
}
