module lmd.model;

import lmd.tool;

interface IModel
{
    ref string key();

    ref string name();

    ref string owner();

    ref Tool[] tools();
}