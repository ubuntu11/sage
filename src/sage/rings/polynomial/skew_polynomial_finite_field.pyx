r"""
This module implements skew polynomials over finite fields.

Let `k` be a finite field and `\sigma` be a ring automorphism
of `k` (i.e. a power of the Frobenius endomorphism). Let
Put `S = k[X,\sigma]`: as an addtive group, it is the usual ring
of polynomials with coefficients in `k` and the multiplication
on `S` is defined by the rule `X * a = \sigma(a) * X`.

.. SEE ALSO::

    - ``Class SkewPolynomial_generic_dense`` and ``Class SkewPolynomial``
        in sage.rings.polynomial.skew_polynomial_element

    - ``Class SkewPolynomialRing`` and ``Class SkewPolynomialRing_finite_field``
        in sage.rings.polynomial.skew_polynomial_ring

We recall that:

#. `S` is a left (resp. right) euclidean noncommutative ring

#. in particular, every left (resp. right) ideal is principal

.. TODO::

    Try to replace as possible ``finite field`` by ``field
    endowed with a finite order twist morphism``. It may cause
    new phenomena due to the non trivality of the Brauer group.

EXAMPLES::

    sage: k.<t> = GF(5^3)
    sage: Frob = k.frobenius_endomorphism()
    sage: S.<x> = k['x',Frob]; S
    Skew Polynomial Ring in x over Finite Field in t of size 5^3 twisted by t |--> t^5

AUTHOR::

- Xavier Caruso (2012-06-29)
"""

#############################################################################
#    Copyright (C) 2012 Xavier Caruso <xavier.caruso@normalesup.org>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#                  http://www.gnu.org/licenses/
#****************************************************************************

include "../../ext/stdsage.pxi"

import copy
import cysignals
from sage.matrix.constructor import zero_matrix
from sage.rings.ring cimport Ring
from polynomial_ring_constructor import PolynomialRing
from skew_polynomial_element cimport SkewPolynomial_generic_dense

cdef class SkewPolynomial_finite_field_dense (SkewPolynomial_generic_dense):

    def __init__(self, parent, x=None, int check=1, is_gen=False, int construct=0, **kwds):
        """
        This method constructs a generic dense skew polynomial over finite field.
        
        INPUT::
            
        - ``parent`` -- parent of `self`

        - ``x`` -- list of coefficients from which `self` can be constructed

        - ``check`` -- flag variable to normalize the polynomial

        - ``is_gen`` -- boolean (default: False)

        - ``construct`` -- boolean (default: False)

        TESTS::

            sage: R.<t> = GF(5^3)
            sage: Frob = R.frobenius_endomorphism()
            sage: S.<x> = R['x',Frob]; S
            Skew Polynomial Ring in x over Finite Field in t of size 5^3 twisted by t |--> t^5

        We create a skew polynomial from a list::

            sage: S([t,1])
            x + t

        from another skew polynomial::

            sage: S(x^2 + t)
            x^2 + t

        from a constant::
        
            sage: x = S(t^2 + 1); x
            t^2 + 1
            sage: x.parent() is S
            True
        """
        SkewPolynomial_generic_dense.__init__ (self, parent, x, check, is_gen, construct, **kwds)

    cdef SkewPolynomial_finite_field_dense _rgcd(self,SkewPolynomial_finite_field_dense other):
        """
        Fast right gcd.
        """
        cdef SkewPolynomial_finite_field_dense A = self
        cdef SkewPolynomial_finite_field_dense B = other
        cdef SkewPolynomial_finite_field_dense swap
        if len(B._coeffs):
            A = <SkewPolynomial_finite_field_dense>self._new_c(A._coeffs[:],A._parent)
            B = <SkewPolynomial_finite_field_dense>B._new_c(B._coeffs[:],B._parent)
            while len(B._coeffs):
                A._inplace_rrem(B)
                swap = A; A = B; B = swap
            return A
        else:
            return self

    cpdef _leftpow_(self, exp, modulus=None):
        """
        INPUT:

        -  ``exp`` -- an Integer

        -  ``modulus`` -- a skew polynomial over the same ring (default: None)

        OUTPUT:

        If ``modulus`` is None, return ``self**exp``.

        Otherwise, return the remainder of self**exp in the left
        euclidean division by ``modulus``.

        REMARK:

        The quotient of the underlying skew polynomial ring by the
        principal ideal generated by ``modulus`` is in general *not*
        a ring.

        As a consequence, Sage first computes exactly ``self**exp``
        and then reduce it modulo ``modulus``.

        However, if the base ring is a finite field, Sage uses the
        following optimized algorithm:

        #. One first compute a central skew polynomial `N` which is
           divisible by ``modulus``. (Since `N` lies in center, the
           quotient `K[X,\sigma]/N` inherits a ring structure.)

        #. One compute ``self**exp`` in the quotient ring `K[X,\sigma]/N`

        #. One reduce modulo ``modulus`` the result computed in the
           previous step

        EXAMPLES::

            sage: k.<t> = GF(5^3)
            sage: Frob = k.frobenius_endomorphism()
            sage: S.<x> = k['x',Frob]
            sage: a = x + t
            sage: b = a._leftpow_(10)

            sage: modulus = x^3 + t*x^2 + (t+3)*x - 2
            sage: br = a._leftpow_(10, modulus); br
            (4*t^2 + 2*t + 3)*x^2 + (3*t^2 + 1)*x + 2*t + 3
            sage: lq, lr = b.left_quo_rem(modulus)
            sage: br == lr
            True

            sage: a._leftpow_(100, modulus)  # rather fast
            (4*t^2 + t + 1)*x^2 + (t^2 + 4*t + 1)*x + 3*t^2 + 3*t
        """
        cdef SkewPolynomial_finite_field_dense r

        if not isinstance(exp, Integer) or isinstance(exp, int):
            try:
                exp = Integer(exp)
            except TypeError:
                raise TypeError("non-integral exponents not supported")

        if self.degree() <= 0:
            r = self.parent()(self[0]**exp)
            return r
        if exp == 0:
            r = self.parent()(1)
            return r
        if exp < 0:
            r = (~self).leftpow(-exp,modulus)
            return r

        if self == self.parent().gen(): # special case x**n should be faster!
            P = self.parent()
            R = P.base_ring()
            v = [R.zero()]*exp + [R.one()]
            r = <SkewPolynomial_generic_dense>self._new_c(v,self._parent)
            if modulus:
                _, r = r.left_quo_rem(modulus)
            return r

        mod = modulus
        if not modulus is None:
            try:
                mod = self.parent()(mod.bound())
            except NotImplementedError:
                mod = None
        r = <SkewPolynomial_generic_dense>self._new_c(copy.copy(self._coeffs),self._parent)
        if mod:
            r._inplace_pow_mod(exp,mod)
        else:
            r._inplace_pow(exp)
        if (not modulus is None) and modulus != mod:
            _, r = r.left_quo_rem(modulus)
        return r

    cpdef _rightpow_(self, exp, modulus=None):
        """
        INPUT:

        -  ``exp`` -- an Integer

        -  ``modulus`` -- a skew polynomial over the same ring (default: None)

        OUTPUT:

        If ``modulus`` is None, return ``self**exp``.

        Otherwise, return the remainder of self**exp in the right
        euclidean division by ``modulus``.

        REMARK:

        The quotient of the underlying skew polynomial ring by the
        principal ideal generated by ``modulus`` is in general *not*
        a ring.

        As a consequence, Sage first computes exactly ``self**exp``
        and then reduce it modulo ``modulus``.

        However, if the base ring is a finite field, Sage uses the
        following optimized algorithm:

        #. One first compute a central skew polynomial `N` which is
           divisible by ``modulus``. (Since `N` lies in center, the
           quotient `K[X,\sigma]/N` inherits a ring structure.)

        #. One compute ``self**exp`` in the quotient ring `K[X,\sigma]/N`

        #. One reduce modulo ``modulus`` the result computed in the
           previous step

        EXAMPLES::

            sage: k.<t> = GF(5^3)
            sage: Frob = k.frobenius_endomorphism()
            sage: S.<x> = k['x',Frob]
            sage: a = x + t
            sage: b = a^10  # short form for ``a._pow_(10)``
            sage: b == a*a*a*a*a*a*a*a*a*a
            True

            sage: modulus = x^3 + t*x^2 + (t+3)*x - 2
            sage: br = a._rightpow_(10, modulus); br
            (t^2 + t)*x^2 + (3*t^2 + 1)*x + t^2 + t
            sage: rq, rr = b.right_quo_rem(modulus)
            sage: br == rr
            True

            sage: a._rightpow_(100, modulus)  # rather fast
            (2*t^2 + 3)*x^2 + (t^2 + 4*t + 2)*x + t^2 + 2*t + 1
        """
        cdef SkewPolynomial_finite_field_dense r

        if not isinstance(exp, Integer) or isinstance(exp, int):
            try:
                exp = Integer(exp)
            except TypeError:
                raise TypeError("non-integral exponents not supported")

        if self.degree() <= 0:
            r = self.parent()(self[0]**exp)
            return r
        if exp == 0:
            r = self.parent()(1)
            return r
        if exp < 0:
            r = (~self).rightpow(-exp,modulus)
            return r

        if self == self.parent().gen(): # special case x**n should be faster!
            P = self.parent()
            R = P.base_ring()
            v = [R.zero()]*exp + [R.one()]
            r = <SkewPolynomial_generic_dense>self._new_c(v,self._parent)
            if modulus:
                _, r = r.right_quo_rem(modulus)
            return r

        mod = modulus
        if not modulus is None:
            try:
                mod = self.parent()(mod.bound())
            except NotImplementedError:
                mod = None
        r = <SkewPolynomial_generic_dense>self._new_c(copy.copy(self._coeffs),self._parent)
        if mod:
            r._inplace_pow_mod(exp,mod)
        else:
            r._inplace_pow(exp)
        if (not modulus is None) and modulus != mod:
            _, r = r.right_quo_rem(modulus)
        return r

    cdef void _inplace_lrem(self, SkewPolynomial_finite_field_dense other):
        """
        Replace self by the remainder in the left euclidean division
        of self by other (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef list b = (<SkewPolynomial_finite_field_dense>other)._coeffs
        cdef Py_ssize_t da = len(a)-1, db = len(b)-1
        cdef Py_ssize_t i, j
        cdef RingElement c, inv
        parent = self._parent
        if db < 0:
            raise ZeroDivisionError
        if da >= db:
            inv = ~b[db]
            for i from da-db >= i >= 0:
                c = parent.twist_map(-db)(inv*a[i+db])
                for j from 0 <= j < db:
                    a[i+j] -= b[j] * parent.twist_map(j)(c)
            del a[db:]
            self.__normalize()

    cdef void _inplace_rrem(self, SkewPolynomial_finite_field_dense other):
        """
        Replace self by the remainder in the right euclidean division
        of self by other (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef list b = (<SkewPolynomial_finite_field_dense>other)._coeffs
        cdef Py_ssize_t da = len(a)-1, db = len(b)-1
        cdef Py_ssize_t i, j, order
        cdef RingElement c, x, inv
        cdef list twinv, twb
        parent = self._parent
        if db < 0:
            raise ZeroDivisionError
        if da >= db:
            order = parent._order
            inv = ~b[db]
            twinv = [ inv ]
            for i from 0 <= i < min(da-db,order-1):
                twinv.append(parent.twist_map()(twinv[i]))
            twb = (<SkewPolynomial_finite_field_dense>other)._conjugates
            for i from len(twb)-1 <= i < min(da-db,order-1):
                twb.append([ parent.twist_map()(x) for x in twb[i] ])
            for i from da-db >= i >= 0:
                c = twinv[i%order] * a[i+db]
                for j from 0 <= j < db:
                    a[i+j] -= c * twb[i%order][j]
            del a[db:]
            self.__normalize()

    cdef void _inplace_lfloordiv(self, SkewPolynomial_finite_field_dense other):
        """
        Replace self by the quotient in the left euclidean division
        of self by other (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef list b = (<SkewPolynomial_finite_field_dense>other)._coeffs
        cdef Py_ssize_t da = len(a)-1, db = len(b)-1
        cdef Py_ssize_t i, j, deb
        cdef RingElement c, inv
        parent = self._parent
        if db < 0:
            sig_off()
            raise ZeroDivisionError
        if da < db:
            (<SkewPolynomial_finite_field_dense>self)._coeffs = [ ]
        else:
            inv = ~b[db]
            for i from da-db >= i >= 0:
                c = a[i+db] = parent.twist_map(-db)(inv*a[i+db])
                if i < db: deb = db
                else: deb = i
                for j from deb <= j < db+i:
                    a[j] -= b[j-i] * parent.twist_map(j-i)(c)
            del a[:db]
            self.__normalize()

    cdef void _inplace_rfloordiv(self, SkewPolynomial_finite_field_dense other):
        """
        Replace self by the quotient in the right euclidean division
        of self by other (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef list b = (<SkewPolynomial_finite_field_dense>other)._coeffs
        cdef Py_ssize_t da = len(a)-1, db = len(b)-1
        cdef Py_ssize_t i, j, deb, order
        cdef RingElement c, x, inv
        parent = self._parent
        if db < 0:
            raise ZeroDivisionError
        if da < db:
            (<SkewPolynomial_finite_field_dense>self)._coeffs = [ ]
        else:
            order = parent._order
            inv = ~b[db]
            twinv = [ inv ]
            for i from 0 <= i < min(da-db,order-1):
                twinv.append(parent.twist_map()(twinv[i]))
            twb = (<SkewPolynomial_finite_field_dense>other)._conjugates
            for i from len(twb)-1 <= i < min(da-db,order-1):
                twb.append([ parent.twist_map()(x) for x in twb[i] ])
            for i from da-db >= i >= 0:
                c = a[i+db] = twinv[i%order] * a[i+db]
                if i < db: deb = db
                else: deb = i
                for j from deb <= j < db+i:
                    a[j] -= c * twb[i%order][j-i]
            del a[:db]
            self.__normalize()

    cdef void _inplace_lmonic(self):
        """
        Replace self by ``self.lmonic()`` (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef Py_ssize_t da = len(a)-1, i
        cdef RingElement inv = ~a[da]
        parent = self._parent
        a[da] = parent.base_ring()(1)
        for i from 0 <= i < da:
            a[i] *= parent.twist_map(i-da)(inv)

    cdef void _inplace_rmonic(self):
        """
        Replace self by ``self.rmonic()`` (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef Py_ssize_t da = len(a)-1, i
        cdef RingElement inv = ~a[da]
        a[da] = self._parent.base_ring()(1)
        for i from 0 <= i < da:
            a[i] *= inv

    cdef void _inplace_rgcd(self,SkewPolynomial_finite_field_dense other):
        """
        Replace self by its right gcd with other (only for internal use).
        """
        cdef SkewPolynomial_finite_field_dense B
        cdef list swap
        if len(other._coeffs):
            B = <SkewPolynomial_finite_field_dense>self._new_c(other._coeffs[:],other._parent)
            while len(B._coeffs):
                B._conjugates = [ B._coeffs ]
                self._inplace_rrem(B)
                swap = self._coeffs
                self._coeffs = B._coeffs
                B._coeffs = swap


    cdef SkewPolynomial_finite_field_dense _rquo_inplace_rem(self, SkewPolynomial_finite_field_dense other):
        """
        Replace self by the remainder in the right euclidean division
        of self by other and return the quotient (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef list b = (<SkewPolynomial_finite_field_dense>other)._coeffs
        cdef Py_ssize_t da = len(a)-1, db = len(b)-1
        cdef Py_ssize_t i, j
        cdef RingElement c, inv
        cdef list q
        parent = self._parent
        if db < 0:
            raise ZeroDivisionError
        if da < db:
            r = self._new_c([],self._parent)
            return r
        inv = ~b[db]
        q = [ ]
        for i from da-db >= i >= 0:
            c = parent.twist_map(i)(inv) * a[i+db]
            q.append(c)
            for j from 0 <= j < db:
                a[i+j] -= c * parent.twist_map(i)(b[j])
        del a[db:]
        self.__normalize()
        q.reverse()
        r = self._new_c(q,self._parent)
        return r

    cdef Py_ssize_t _val_inplace_unit(self):
        """
        Return `v` the valuation of self and replace self by
        self >> v (only for internal use).
        """
        cdef list a = (<SkewPolynomial_finite_field_dense>self)._coeffs
        cdef Py_ssize_t val = 0
        if len(a) < 0:
            sig_off()
            return -1
        while a[0].is_zero():
            del a[0]
            val += 1
        return val

    cdef Matrix_dense _matmul_c(self):
        r"""
        Return the matrix of the multiplication by self on
        `K[X,\sigma]` considered as a free module over `K[X^r]`
        (here `r` is the order of `\sigma`).

        .. WARNING::

            Does not work if self is not monic.
        """
        cdef Py_ssize_t i, j, deb, k, r = self.parent()._order
        cdef Py_ssize_t d = self.degree ()
        cdef Ring base_ring = <Ring?>self.parent().base_ring()
        cdef RingElement minusone = <RingElement?>base_ring(-1)
        cdef RingElement zero = <RingElement?>base_ring(0)
        cdef Polk = PolynomialRing (base_ring, 'xr')
        cdef Matrix_dense M = <Matrix_dense?>zero_matrix(Polk,r,r)
        cdef list l = self.list()
        for j from 0 <= j < r:
            for i from 0 <= i < r:
                if i < j:
                    pol = [ zero ]
                    deb = i-j+r
                else:
                    pol = [ ]
                    deb = i-j
                for k from deb <= k <= d by r:
                    pol.append(l[k])
                M.set_unsafe(i,j,Polk(pol))
            for i from 0 <= i <= d:
                l[i] = self._parent.twist_map()(l[i])
        return M
