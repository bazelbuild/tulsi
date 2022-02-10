"""version.bzl: Contains constants and rules for Tulsi versioning.
"""

# Version number (recorded into the Info.plist)
TULSI_VERSION_MAJOR = "0"

TULSI_VERSION_FIXLEVEL = "427587075"

TULSI_VERSION_DATE = "20220209"

TULSI_VERSION_COPYRIGHT = "2015-2018"

TULSI_PRODUCT_NAME = "Tulsi"

GOOGLE_VERSION_BUILDNUMBER = "4"

#
# Build things out of the parts.
#
TULSI_VERSIONINFO_LONG = "%s.%s.%s" % (
    TULSI_VERSION_MAJOR,
    TULSI_VERSION_DATE,
    TULSI_VERSION_FIXLEVEL,
)

TULSI_VERSIONINFO_ABOUT = "%s %s\n © %s The Tulsi Authors." % (
    TULSI_PRODUCT_NAME,
    TULSI_VERSIONINFO_LONG,
    TULSI_VERSION_COPYRIGHT,
)

def fill_info_plist_impl(ctx):
    ctx.actions.expand_template(
        template = ctx.file.template,
        output = ctx.outputs.out,
        substitutions = {
            "$(TULSI_VERSIONINFO_ABOUT)": TULSI_VERSIONINFO_ABOUT,
            "$(PRODUCT_MODULE_NAME)": TULSI_PRODUCT_NAME,
        },
    )

fill_info_plist = rule(
    attrs = {
        "template": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "out": attr.output(mandatory = True),
    },
    implementation = fill_info_plist_impl,
)
