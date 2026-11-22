# Sale quantity precision

New catalog and custom sale lines accept decimal quantities from `0.001` through `1000000`, with three meaningful fractional digits. Surrounding spaces, leading zeros, and trailing fractional zeros are accepted by the editors. Signs and exponent notation are rejected in new editor input. Normalize valid quantities before preview and posting. An invalid quantity remains editable and recoverable and blocks a new review or save. A frozen retry retains its original request and identity.

The API retains its existing wire compatibility. The sale editor and report validation leave catalog, receiving, stock and historical invoice quantities at their existing precision. A sale amount with a fourth meaningful fractional digit requires an explicit correction and is never rounded to a different sale quantity.
