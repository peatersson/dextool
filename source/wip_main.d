/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module app;

import std.conv;
import std.typecons : Nullable, Flag;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import wip = generator.analyze.wip;
import generator.clangcontext;
import generator.analyzer;
import generator.analyze.containers : AccessType;

import generator.stub.misc;

/** Descend a class cursor to extract interior information.
 * C'tors, d'tors, member methods etc.
 * Cleanly separates the functionality for initializing the container for a
 * class and the analyze logic.
 *
 * Note that it also traverses the inheritance chain.
 */
struct ClassDescendVisitor {
    import generator.analyze.containers;
    import std.typecons : NullableRef;

    @disable this();

    this(NullableRef!CppClass data) {
        if (data.isNull) {
            logger.fatal("CppClass parameter is null");
            throw new Exception("CppClass parameter is null");
        }
        this.data = &data.get();
        this.accessType = CppMethodAccess(AccessType.Private);
    }

    void visit(ref Cursor c) {
        wip.visitAst!(typeof(this))(c, this);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_Constructor:
            applyConstructor(c, parent);
            descend = false;
            break;
        case CXCursor_Destructor:
            applyDestructor(c, parent);
            descend = false;
            break;
        case CXCursor_CXXMethod:
            applyMethod(c, parent);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            this.accessType = CppMethodAccess(toAccessType(c.access.accessSpecifier));
            break;
        case CXCursor_CXXBaseSpecifier:
            break;
        default:
            break;
        }
        return descend;
    }

private:
    void applyConstructor(ref Cursor c, ref Cursor parent) {
        auto params = paramDeclTo!CppParam(c);
        auto name = CppMethodName(c.spelling);
        auto tor = CppTorMethod(name, params, accessType, CppVirtualMethod(VirtualType.No));
        logger.info("ctor: ", tor.toString);
        data.put(tor);
    }

    void applyDestructor(ref Cursor c, ref Cursor parent) {
        auto params = paramDeclTo!CppParam(c);
        auto name = CppMethodName(c.spelling);
        auto tor = CppTorMethod(name, params, accessType,
            CppVirtualMethod(c.func.isVirtual ? VirtualType.Yes : VirtualType.No));
        logger.info("dtor: ", tor.toString);
        data.put(tor);
    }

    void applyMethod(ref Cursor c, ref Cursor parent) {
        import translator.Type : TypeKind, translateType;

        auto params = paramDeclTo!CppParam(c);
        auto name = CppMethodName(c.spelling);
        auto return_type = CppReturnType(translateType(c.func.resultType));

        auto is_virtual = CppVirtualMethod(VirtualType.No);
        if (c.func.isPureVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Pure);
        } else if (c.func.isVirtual) {
            is_virtual = CppVirtualMethod(VirtualType.Yes);
        }

        auto method = CppMethod(name, params, return_type, accessType,
            CppConstMethod(c.func.isConst), is_virtual);
        logger.info("method: ", method.toString);
        data.put(method);
    }

private:
    CppClass* data;
    CppMethodAccess accessType;
}

/** Extract information about a class.
 *
 * The constructor is disabled to force the class to be in a consistent state.
 * static make to create ClassVisitor objects to avoid the unnecessary storage
 * of a Cursor but still derive parameters from the Cursor.
 */
struct ClassVisitor {
    import generator.analyze.containers;
    import std.typecons : NullableRef;

    /** Make a ClassVisitor by deriving the name and virtuality from a Clang Cursor.
     */
    static auto make(ref Cursor c) {
        auto name = CppClassName(c.spelling);
        auto isVirtual = CppVirtualClass(c.isVirtualBase ? VirtualType.Pure : VirtualType.No);

        auto r = ClassVisitor(name, isVirtual);
        return r;
    }

    @disable this();

    private this(CppClassName name, CppVirtualClass virtual) {
        this.data = CppClass(name, virtual);
    }

    auto visit(ref Cursor c) {
        if (!c.isDefinition) {
            logger.error("Expected cursor to be a definition but it is:", to!string(c));
            return data;
        }
        auto d = NullableRef!CppClass(&data);
        ClassDescendVisitor(d).visit(c);

        return data;
    }

private:
    CppClass data;
}

AccessType toAccessType(CX_CXXAccessSpecifier accessSpec) {
    final switch (accessSpec) with (CX_CXXAccessSpecifier) {
    case CX_CXXInvalidAccessSpecifier:
        return AccessType.Public;
    case CX_CXXPublic:
        return AccessType.Public;
    case CX_CXXProtected:
        return AccessType.Protected;
    case CX_CXXPrivate:
        return AccessType.Private;
    }
}

/// Context for AST visit.
struct ParseContext {
    import generator.analyze.containers;

    private VisitNodeDepth depth_;
    alias depth_ this;

    void visit(Cursor cursor) {
        wip.visitAst!(typeof(this))(cursor, this);
    }

    bool apply(ref Cursor c, ref Cursor parent) {
        bool descend = true;
        logNode(c, depth);
        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            root.put(ClassVisitor.make(c).visit(c));
            break;

        default:
            break;
        }

        return descend;
    }

    CppRoot root;
}

int main(string[] args) {
    import std.stdio;

    logger.globalLogLevel(logger.LogLevel.all);
    logger.info("WIP mode");
    if (args.length < 2) {
        logger.info("Unittesting");
        return 0;
    }

    auto infile = to!string(args[1]);
    auto file_ctx = new ClangContext(infile);
    file_ctx.logDiagnostic;
    if (file_ctx.hasParseErrors)
        return 1;

    logger.infof("Testing '%s'", infile);

    ParseContext foo;
    foo.visit(file_ctx.cursor);
    writeln("Content from root: ", foo.root.toString);

    return 0;
}
