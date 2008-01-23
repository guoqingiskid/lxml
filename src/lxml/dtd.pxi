# support for DTD validation
cimport dtdvalid

class DTDError(LxmlError):
    """Base class for DTD errors.
    """
    pass

class DTDParseError(DTDError):
    """Error while parsing a DTD.
    """
    pass

class DTDValidateError(DTDError):
    """Error while validating an XML document with a DTD.
    """
    pass

################################################################################
# DTD

cdef class DTD(_Validator):
    """A DTD validator.

    Can load from filesystem directly given a filename or file-like object.
    Alternatively, pass the keyword parameter ``external_id`` to load from a
    catalog.
    """
    cdef tree.xmlDtd* _c_dtd
    def __init__(self, file=None, *, external_id=None):
        self._c_dtd = NULL
        _Validator.__init__(self)
        if file is not None:
            if python._isString(file):
                self._error_log.connect()
                self._c_dtd = xmlparser.xmlParseDTD(NULL, _cstr(file))
                self._error_log.disconnect()
            elif hasattr(file, 'read'):
                self._c_dtd = _parseDtdFromFilelike(file)
            else:
                raise DTDParseError("file must be a filename or file-like object")
        elif external_id is not None:
            self._error_log.connect()
            self._c_dtd = xmlparser.xmlParseDTD(external_id, NULL)
            self._error_log.disconnect()
        else:
            raise DTDParseError("either filename or external ID required")

        if self._c_dtd is NULL:
            raise DTDParseError(
                self._error_log._buildExceptionMessage("error parsing DTD"),
                error_log=self._error_log)

    def __dealloc__(self):
        tree.xmlFreeDtd(self._c_dtd)

    def __call__(self, etree):
        """Validate doc using the DTD.

        Returns true if the document is valid, false if not.
        """
        cdef _Document doc
        cdef _Element root_node
        cdef xmlDoc* c_doc
        cdef dtdvalid.xmlValidCtxt* valid_ctxt
        cdef int ret

        doc = _documentOrRaise(etree)
        root_node = _rootNodeOrRaise(etree)

        self._error_log.connect()
        valid_ctxt = dtdvalid.xmlNewValidCtxt()
        if valid_ctxt is NULL:
            self._error_log.disconnect()
            raise DTDError, "Failed to create validation context"

        c_doc = _fakeRootDoc(doc._c_doc, root_node._c_node)
        with nogil:
            ret = dtdvalid.xmlValidateDtd(valid_ctxt, c_doc, self._c_dtd)
        _destroyFakeDoc(doc._c_doc, c_doc)

        dtdvalid.xmlFreeValidCtxt(valid_ctxt)

        self._error_log.disconnect()
        if ret == -1:
            raise DTDValidateError("Internal error in DTD validation")
        if ret == 1:
            return True
        else:
            return False


cdef tree.xmlDtd* _parseDtdFromFilelike(file) except NULL:
    cdef _ExceptionContext exc_context
    cdef _FileReaderContext dtd_parser
    cdef _ErrorLog error_log
    cdef tree.xmlDtd* c_dtd
    exc_context = _ExceptionContext()
    dtd_parser = _FileReaderContext(file, exc_context, None, None)
    error_log = _ErrorLog()

    error_log.connect()
    c_dtd = dtd_parser._readDtd()
    error_log.disconnect()

    exc_context._raise_if_stored()
    if c_dtd is NULL:
        raise DTDParseError("error parsing DTD", error_log=error_log)
    return c_dtd

cdef extern from "etree_defs.h":
    # macro call to 't->tp_new()' for fast instantiation
    cdef DTD NEW_DTD "PY_NEW" (object t)

cdef DTD _dtdFactory(tree.xmlDtd* c_dtd):
    # do not run through DTD.__init__()!
    cdef DTD dtd
    if c_dtd is NULL:
        return None
    dtd = NEW_DTD(DTD)
    dtd._c_dtd = tree.xmlCopyDtd(c_dtd)
    if dtd._c_dtd is NULL:
        python.PyErr_NoMemory()
    _Validator.__init__(dtd)
    return dtd
