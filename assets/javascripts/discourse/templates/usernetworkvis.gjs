import bodyClass from "discourse/helpers/body-class";
import Usernetworkvis from "../components/usernetworkvis";

<template>
  {{bodyClass "has-user-network-vis"}}
  <Usernetworkvis @model={{@model}} />
</template>
