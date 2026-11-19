import React from 'react';
import {hubspot} from '@hubspot/ui-extensions';
import {createPageRouter,PageRoutes} from '@hubspot/ui-extensions/pages';
import {OverviewPage} from './OverviewPage';
const Router=createPageRouter(<PageRoutes><PageRoutes.IndexRoute component={OverviewPage}/></PageRoutes>);
hubspot.extend<'pages'>(()=><Router/>);
