// python-gphoto2 - Python interface to libgphoto2
// http://github.com/jim-easterbrook/python-gphoto2
// Copyright (C) 2014-17  Jim Easterbrook  jim@jim-easterbrook.me.uk
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

%module(package="gphoto2") context

%include "common/preamble.i"

%rename(Context) _GPContext;

#ifndef SWIGIMPORTED

// Make docstring parameter types more Pythonic
%typemap(doc) GPContext * "$1_name: Context";

// gp_camera_autodetect() returns a pointer in an output parameter
NEW_ARGOUT(CameraList *, gp_list_new, gp_list_unref)

// Ignore "backend" functions
%ignore gp_context_cancel;
%ignore gp_context_error;
%ignore gp_context_idle;
%ignore gp_context_message;
%ignore gp_context_progress_start;
%ignore gp_context_progress_stop;
%ignore gp_context_progress_update;
%ignore gp_context_question;
%ignore gp_context_ref;
%ignore gp_context_status;
%ignore gp_context_unref;

#if GPHOTO2_VERSION < 0x020500
%ignore gp_context_set_idle_func;
%ignore gp_context_set_error_func;
%ignore gp_context_set_message_func;
%ignore gp_context_set_question_func;
%ignore gp_context_set_cancel_func;
%ignore gp_context_set_progress_funcs;
%ignore gp_context_set_status_func;

#else // GPHOTO2_VERSION < 0x020500

// Macro for the six single callback function variants
%define SINGLE_CALLBACK_FUNCTION(data_type, cb_func_type, install_func, cb_wrapper)

// Define the struct
%ignore data_type::context;
%ignore data_type::func;
%ignore data_type::data;
%inline %{
typedef struct data_type {
    GPContext   *context;
    PyObject    *func;
    PyObject    *data;
} data_type;
%}
// Add destructor
%extend data_type {
    ~data_type() {
        install_func($self->context, NULL, NULL);
        Py_DECREF($self->func);
        Py_DECREF($self->data);
        free($self);
    }
};
// Define typemaps
%typemap(arginit) cb_func_type func (data_type *_global_callbacks) {
    _global_callbacks = malloc(sizeof(data_type));
    if (!_global_callbacks) {
        PyErr_SetNone(PyExc_MemoryError);
        SWIG_fail;
    }
    _global_callbacks->context = NULL;
    _global_callbacks->func = NULL;
    _global_callbacks->data = NULL;
}
%typemap(in) cb_func_type func {
    if (!PyCallable_Check($input)) {
        SWIG_exception_fail(SWIG_TypeError, "in method '" "$symname" "', argument " "$argnum" " is not callable");
    }
    _global_callbacks->func = $input;
    Py_INCREF(_global_callbacks->func);
    $1 = (cb_func_type) cb_wrapper;
}
%typemap(argout) cb_func_type func {
    $result = SWIG_Python_AppendOutput($result,
        SWIG_NewPointerObj(_global_callbacks, SWIGTYPE_p_ ## data_type, SWIG_POINTER_OWN));
    _global_callbacks = NULL;
}
%enddef // SINGLE_CALLBACK_FUNCTION

SINGLE_CALLBACK_FUNCTION(IdleCallback, GPContextIdleFunc,
                         gp_context_set_idle_func, wrap_idle_func)
SINGLE_CALLBACK_FUNCTION(ErrorCallback, GPContextErrorFunc,
                         gp_context_set_error_func, wrap_error_func)
SINGLE_CALLBACK_FUNCTION(StatusCallback, GPContextStatusFunc,
                         gp_context_set_status_func, wrap_status_func)
SINGLE_CALLBACK_FUNCTION(MessageCallback, GPContextMessageFunc,
                         gp_context_set_message_func, wrap_message_func)
SINGLE_CALLBACK_FUNCTION(QuestionCallback, GPContextQuestionFunc,
                         gp_context_set_question_func, wrap_question_func)
SINGLE_CALLBACK_FUNCTION(CancelCallback, GPContextCancelFunc,
                         gp_context_set_cancel_func, wrap_cancel_func)

// Progress callbacks are more complicated
%ignore ProgressCallbacks::context;
%ignore ProgressCallbacks::func_1;
%ignore ProgressCallbacks::func_2;
%ignore ProgressCallbacks::func_3;
%ignore ProgressCallbacks::data;

%inline %{
typedef struct ProgressCallbacks {
    GPContext   *context;
    PyObject    *func_1;
    PyObject    *func_2;
    PyObject    *func_3;
    PyObject    *data;
} ProgressCallbacks;
%}

%extend ProgressCallbacks {
    ~ProgressCallbacks() {
        gp_context_set_progress_funcs($self->context, NULL, NULL, NULL, NULL);
        Py_DECREF($self->func_1);
        Py_DECREF($self->func_2);
        Py_DECREF($self->func_3);
        Py_DECREF($self->data);
        free($self);
    }
};

// Macros for wrappers around Python callbacks
%define CB_PREAMBLE
%{
    PyGILState_STATE gstate = PyGILState_Ensure();
    PyObject *result = NULL;
    PyObject *arglist = NULL;
    PyObject *self = NULL;
    PyObject *py_context = SWIG_NewPointerObj(SWIG_as_voidptr(context), SWIGTYPE_p__GPContext, 0);
%}
%enddef

%define CB_POSTAMBLE
%{
        Py_DECREF(arglist);
        if (result == NULL) {
            PyErr_Print();
        } else {
            Py_DECREF(result);
        }
    }
    PyGILState_Release(gstate);
%}
%enddef

%{
// Call Python callbacks from C callbacks
static void wrap_idle_func(GPContext *context, void *data) {
    IdleCallback *this = data;
%}
CB_PREAMBLE
%{
    arglist = Py_BuildValue("(OO)", py_context, this->data);
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
%}
CB_POSTAMBLE
%{
};

static void wrap_error_func(GPContext *context, const char *text, void *data) {
    ErrorCallback *this = data;
%}
CB_PREAMBLE
%{
#if PY_VERSION_HEX >= 0x03000000
    arglist = Py_BuildValue("(OyO)", py_context, text, this->data);
#else
    arglist = Py_BuildValue("(OsO)", py_context, text, this->data);
#endif
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
%}
CB_POSTAMBLE
%{
};

static void wrap_status_func(GPContext *context, const char *text, void *data) {
    StatusCallback *this = data;
%}
CB_PREAMBLE
%{
#if PY_VERSION_HEX >= 0x03000000
    arglist = Py_BuildValue("(OyO)", py_context, text, this->data);
#else
    arglist = Py_BuildValue("(OsO)", py_context, text, this->data);
#endif
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
%}
CB_POSTAMBLE
%{
};

static void wrap_message_func(GPContext *context, const char *text, void *data) {
    MessageCallback *this = data;
%}
CB_PREAMBLE
%{
#if PY_VERSION_HEX >= 0x03000000
    arglist = Py_BuildValue("(OyO)", py_context, text, this->data);
#else
    arglist = Py_BuildValue("(OsO)", py_context, text, this->data);
#endif
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
%}
CB_POSTAMBLE
%{
};

static GPContextFeedback wrap_question_func(GPContext *context, const char *text, void *data) {
    QuestionCallback *this = data;
    GPContextFeedback c_result = GP_CONTEXT_FEEDBACK_OK;
%}
CB_PREAMBLE
%{
#if PY_VERSION_HEX >= 0x03000000
    arglist = Py_BuildValue("(OyO)", py_context, text, this->data);
#else
    arglist = Py_BuildValue("(OsO)", py_context, text, this->data);
#endif
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
        if (result) {
            c_result = PyInt_AsLong(result);
        }
%}
CB_POSTAMBLE
%{
    return c_result;
};

static GPContextFeedback wrap_cancel_func(GPContext *context, void *data) {
    CancelCallback *this = data;
    GPContextFeedback c_result = GP_CONTEXT_FEEDBACK_OK;
%}
CB_PREAMBLE
%{
    arglist = Py_BuildValue("(OO)", py_context, this->data);
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func, arglist);
        if (result) {
            c_result = PyInt_AsLong(result);
        }
%}
CB_POSTAMBLE
%{
    return c_result;
};

static int py_progress_start(GPContext *context, float target, const char *text, void *data) {
    ProgressCallbacks *this = data;
    int c_result = 0;
%}
CB_PREAMBLE
%{
#if PY_VERSION_HEX >= 0x03000000
    arglist = Py_BuildValue("(OfyO)", py_context, target, text, this->data);
#else
    arglist = Py_BuildValue("(OfsO)", py_context, target, text, this->data);
#endif
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func_1, arglist);
        if (result) {
            c_result = PyInt_AsLong(result);
            if ((c_result == -1) && PyErr_Occurred())
                PyErr_Print();
        }
%}
CB_POSTAMBLE
%{
    return c_result;
};

static void py_progress_update(GPContext *context, unsigned int id, float current, void *data) {
    ProgressCallbacks *this = data;
%}
CB_PREAMBLE
%{
    arglist = Py_BuildValue("(OifO)", py_context, id, current, this->data);
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func_2, arglist);
%}
CB_POSTAMBLE
%{
};

static void py_progress_stop(GPContext *context, unsigned int id, void *data) {
    ProgressCallbacks *this = data;
%}
CB_PREAMBLE
%{
    arglist = Py_BuildValue("(OiO)", py_context, id, this->data);
    if (arglist == NULL) {
        PyErr_Print();
    } else {
        result = PyObject_CallObject(this->func_3, arglist);
%}
CB_POSTAMBLE
%{
};

%}

// Use typemaps to install callbacks
%typemap(arginit) GPContextProgressStartFunc start_func (ProgressCallbacks *_global_callbacks) {
    _global_callbacks = malloc(sizeof(ProgressCallbacks));
    if (!_global_callbacks) {
        PyErr_SetNone(PyExc_MemoryError);
        SWIG_fail;
    }
    _global_callbacks->context = NULL;
    _global_callbacks->func_1 = NULL;
    _global_callbacks->func_2 = NULL;
    _global_callbacks->func_3 = NULL;
    _global_callbacks->data = NULL;
}
%typemap(freearg) void *data {
    free(_global_callbacks);
}

%typemap(in) void *data {
    _global_callbacks->data = $input;
    Py_INCREF(_global_callbacks->data);
    $1 = _global_callbacks;
}

%typemap(check) GPContext *context {
    _global_callbacks->context = $1;
}

%typemap(in) GPContextProgressStartFunc {
    if (!PyCallable_Check($input)) {
        SWIG_exception_fail(SWIG_TypeError, "in method '" "$symname" "', argument " "$argnum" " is not callable");
    }
    _global_callbacks->func_1 = $input;
    Py_INCREF(_global_callbacks->func_1);
    $1 = (GPContextProgressStartFunc) py_progress_start;
}

%typemap(in) GPContextProgressUpdateFunc {
    if (!PyCallable_Check($input)) {
        SWIG_exception_fail(SWIG_TypeError, "in method '" "$symname" "', argument " "$argnum" " is not callable");
    }
    _global_callbacks->func_2 = $input;
    Py_INCREF(_global_callbacks->func_2);
    $1 = (GPContextProgressUpdateFunc) py_progress_update;
}

%typemap(in) GPContextProgressStopFunc {
    if (!PyCallable_Check($input)) {
        SWIG_exception_fail(SWIG_TypeError, "in method '" "$symname" "', argument " "$argnum" " is not callable");
    }
    _global_callbacks->func_3 = $input;
    Py_INCREF(_global_callbacks->func_3);
    $1 = (GPContextProgressStopFunc) py_progress_stop;
}

%typemap(argout) GPContextProgressStartFunc {
    $result = SWIG_Python_AppendOutput($result,
        SWIG_NewPointerObj(_global_callbacks, SWIGTYPE_p_ProgressCallbacks, SWIG_POINTER_OWN));
    _global_callbacks = NULL;
}

// Add member methods to _GPContext
MEMBER_FUNCTION(_GPContext, Context,
    camera_autodetect, (CameraList *list),
    gp_camera_autodetect, (list, $self))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_idle_func, (GPContextIdleFunc func, void *data),
    gp_context_set_idle_func, ($self, func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_error_func, (GPContextErrorFunc func, void *data),
    gp_context_set_error_func, ($self, func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_message_func, (GPContextMessageFunc func, void *data),
    gp_context_set_message_func, ($self, func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_question_func, (GPContextQuestionFunc func, void *data),
    gp_context_set_question_func, ($self, func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_cancel_func, (GPContextCancelFunc func, void *data),
    gp_context_set_cancel_func, ($self, func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_progress_funcs, (GPContextProgressStartFunc start_func,
                         GPContextProgressUpdateFunc update_func,
                         GPContextProgressStopFunc stop_func,
                         void *data),
    gp_context_set_progress_funcs, ($self, start_func, update_func, stop_func, data))
VOID_MEMBER_FUNCTION(_GPContext, Context,
    set_status_func, (GPContextStatusFunc func, void *data),
    gp_context_set_status_func, ($self, func, data))

#endif // GPHOTO2_VERSION >= 0x020500

#endif //ifndef SWIGIMPORTED

// Add default constructor and destructor
struct _GPContext {};
%extend _GPContext {
  _GPContext() {
    return gp_context_new();
  }
  ~_GPContext() {
    gp_context_unref($self);
  }
};
%ignore _GPContext;
%newobject gp_context_new;
%delobject gp_context_unref;

%include "gphoto2/gphoto2-context.h"
