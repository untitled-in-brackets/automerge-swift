use super::UniffiCustomTypeConverter;
use automerge as am;

#[derive(Debug, Clone)]
pub struct ObjId(Vec<u8>);

impl From<ObjId> for automerge::ObjId {
    fn from(value: ObjId) -> Self {
        // There is no way to construct ObjId except in this library, where we always construct it
        // from a valid object ID byte array am::ObjId::try_from(&value.0[..]).unwrap()
        am::ObjId::try_from(value.0.as_slice()).unwrap()
    }
}

impl From<am::ObjId> for ObjId {
    fn from(value: am::ObjId) -> Self {
        // trailing actor index is a doc-local lookup hint that shifts after merges;
        // zero it so the same object always serializes identically (swift compares bytes)
        let normalized = match value {
            am::ObjId::Id(counter, actor, _) => am::ObjId::Id(counter, actor, 0),
            root => root,
        };
        ObjId(normalized.to_bytes())
    }
}

pub fn root() -> ObjId {
    am::ROOT.into()
}

impl UniffiCustomTypeConverter for ObjId {
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
