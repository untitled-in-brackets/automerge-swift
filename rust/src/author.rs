use automerge as am;

use super::UniffiCustomTypeConverter;

pub struct Author(Vec<u8>);

impl From<Author> for am::Author<'static> {
    fn from(value: Author) -> Self {
        am::Author::from(value.0)
    }
}

impl<'a> From<am::Author<'a>> for Author {
    fn from(value: am::Author<'a>) -> Self {
        Author(value.as_bytes().to_vec())
    }
}

impl<'a> From<&'a am::Author<'a>> for Author {
    fn from(value: &'a am::Author<'a>) -> Self {
        Author(value.as_bytes().to_vec())
    }
}

impl UniffiCustomTypeConverter for Author {
    type Builtin = Vec<u8>;

    fn into_custom(val: Self::Builtin) -> uniffi::Result<Self>
    where
        Self: Sized,
    {
        Ok(Self(val))
    }

    fn from_custom(obj: Self) -> Self::Builtin {
        obj.0
    }
}
