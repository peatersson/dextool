/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.test_analyzer;

import std.path : relativePath;

import dextool.plugin.mutate.backend.database.standalone;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type;
static import dextool.type;

import dextool_test.utility;

// dfmt off

@(testId ~ "shall analyze the provided file")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextoolAnalyze(testEnv)
        .addInputArg(testData ~ "all_kinds_of_abs_mutation_points.cpp")
        .run;
}

@(testId ~ "shall exclude files from the analysis they are part of an excluded directory tree when analysing")
unittest {
    mixin(EnvSetup(globalTestdir));

    const programFile1 = testData ~ "analyze/file1.cpp";
    const programFile2 = testData ~ "analyze/exclude/file2.cpp";

    makeDextoolAnalyze(testEnv)
        .addInputArg(programFile1)
        .addInputArg(programFile2)
        .addPostArg(["--file-exclude", (testData ~ "analyze/exclude").toString])
        .run;

    // assert
    auto db = Database.make((testEnv.outdir ~ defaultDb).toString);

    const file1 = dextool.type.Path(relativePath(programFile1.toString, workDir.toString));
    const file2 = dextool.type.Path(relativePath(programFile2.toString, workDir.toString));

    db.getFileId(file1).isNull.shouldBeFalse;
    db.getFileId(file2).isNull.shouldBeTrue;
}
